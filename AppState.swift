import Foundation
import Combine
import AppKit
import ImageIO

// Performance characteristics (verified 2026-02-02):
// - Loads ~100 images in ~2-3 seconds (background enumeration)
// - Thumbnail cache provides instant second viewing
// - NSCache evicts under memory pressure (100MB limit, 100 image max)
// - Slideshow transitions at 3s interval are smooth

class AppState: ObservableObject {
    @Published var images: [ImageFile] = []
    @Published var currentImageIndex: Int = 0
    @Published var selectedFolder: URL?
    @Published var isSlideshowRunning: Bool = false
    @Published var slideshowInterval: Double = 3.0 // seconds
    @Published var sortOrder: SortOrder = .name
    @Published var customOrder: [String] = [] // filenames in custom order
    @Published var failedImages: Set<URL> = []
    @Published var isLoadingImages: Bool = false

    private var slideshowTimer: Timer?
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, CGImage>()
    private let mainImageCache = NSCache<NSString, CGImage>()
    private let imageLoadQueue = DispatchQueue(label: "ImageBrowser.imageLoad", qos: .userInitiated, attributes: .concurrent)
    private let thumbnailCacheLimit = 1000
    private var thumbnailPrefetchMaxPixelSize = 0
    private var thumbnailPrefetchTask: Task<Void, Never>?
    private let thumbnailPrefetchBatchSize = 48
    private let thumbnailPrefetchBatchDelayNanoseconds: UInt64 = 120_000_000
    private let fileSystem: FileSystemProviding
    private let preferencesStore: PreferencesStore

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case creationDate = "Creation Date"
        case custom = "Custom Order"
    }
    
    init(
        fileSystem: FileSystemProviding = LocalFileSystem(),
        preferencesStore: PreferencesStore = UserDefaultsPreferencesStore()
    ) {
        self.fileSystem = fileSystem
        self.preferencesStore = preferencesStore
        loadPreferences()
        applyTestFolderOverrideIfNeeded()
        imageCache.totalCostLimit = 1024 * 1024 * 100  // 100 MB
        imageCache.countLimit = 100  // Max 100 cached images

        thumbnailCache.totalCostLimit = 1024 * 1024 * 50  // 50 MB
        thumbnailCache.countLimit = thumbnailCacheLimit

        mainImageCache.totalCostLimit = 1024 * 1024 * 300  // 300 MB
        mainImageCache.countLimit = 50
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
            loadImages(from: url)
        }
    }
    
    func loadImages(from url: URL) {
        failedImages.removeAll()
        isLoadingImages = true
        thumbnailPrefetchTask?.cancel()

        DispatchQueue.global(qos: .userInitiated).async {
            var foundImages: [ImageFile] = []

            if let enumerator = self.fileSystem.enumerator(
                at: url,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                while case let fileURL as URL = enumerator.nextObject() {
                    if self.isImageFile(fileURL) {
                        do {
                            let attributes = try self.fileSystem.attributesOfItem(atPath: fileURL.path)
                            if let creationDate = attributes[.creationDate] as? Date {
                                let imageFile = ImageFile(
                                    url: fileURL,
                                    name: fileURL.lastPathComponent,
                                    creationDate: creationDate
                                )
                                foundImages.append(imageFile)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.failedImages.insert(fileURL)
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.sortImages(&foundImages)
                self.images = foundImages
                self.currentImageIndex = 0
                self.isLoadingImages = false
                self.savePreferences()
                self.startThumbnailPrefetchIfNeeded()
            }
        }
    }
    
    private func isImageFile(_ url: URL) -> Bool {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
    
    func sortImages(_ images: inout [ImageFile]) {
        switch sortOrder {
        case .name:
            images.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .creationDate:
            images.sort { $0.creationDate < $1.creationDate }
        case .custom:
            if !customOrder.isEmpty {
                images.sort { image1, image2 in
                    let index1 = customOrder.firstIndex(of: image1.name) ?? Int.max
                    let index2 = customOrder.firstIndex(of: image2.name) ?? Int.max
                    return index1 < index2
                }
            }
        }
    }
    
    func resortImages() {
        var sortedImages = images
        sortImages(&sortedImages)
        
        // Preserve current image if possible
        if let currentImage = images[safe: currentImageIndex] {
            if let newIndex = sortedImages.firstIndex(where: { $0.url == currentImage.url }) {
                currentImageIndex = newIndex
            }
        }
        
        images = sortedImages
        savePreferences()
    }
    
    func navigateToNext() {
        guard !images.isEmpty else { return }
        currentImageIndex = (currentImageIndex + 1) % images.count
    }
    
    func navigateToPrevious() {
        guard !images.isEmpty else { return }
        currentImageIndex = (currentImageIndex - 1 + images.count) % images.count
    }
    
    func navigateToIndex(_ index: Int) {
        guard index >= 0 && index < images.count else { return }
        currentImageIndex = index
    }
    
    func clearFailedImages() {
        failedImages.removeAll()
    }

    func loadImage(from url: URL) -> NSImage? {
        let cacheKey = url.absoluteString as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        if let image = NSImage(contentsOf: url) {
            // Estimate cost based on pixel count (width × height × 4 bytes per pixel)
            let cost = estimateImageCost(image)
            imageCache.setObject(image, forKey: cacheKey, cost: cost)
            return image
        }

        return nil
    }

    private func estimateImageCost(_ image: NSImage) -> Int {
        guard let tiffRep = image.tiffRepresentation else { return 1024 }
        return tiffRep.count
    }

    enum ImageCacheKind {
        case thumbnail
        case main
    }

    func loadDownsampledImage(from url: URL, maxPixelSize: Int, cache: ImageCacheKind) async -> CGImage? {
        guard maxPixelSize > 0 else { return nil }
        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        let cacheStore = cache == .thumbnail ? thumbnailCache : mainImageCache

        if let cachedImage = cacheStore.object(forKey: cacheKey) {
            return cachedImage
        }

        return await withCheckedContinuation { continuation in
            imageLoadQueue.async {
                let image = Self.downsampleImage(at: url, maxPixelSize: maxPixelSize)
                if let image = image {
                    let cost = Self.estimateImageCost(image)
                    cacheStore.setObject(image, forKey: cacheKey, cost: cost)
                }
                continuation.resume(returning: image)
            }
        }
    }

    func prefetchMainImages(around index: Int, maxPixelSize: Int) {
        guard !images.isEmpty else { return }
        let neighborIndices = [index - 1, index + 1]
            .filter { $0 >= 0 && $0 < images.count }

        for neighborIndex in neighborIndices {
            let url = images[neighborIndex].url
            Task.detached(priority: .utility) { [weak self] in
                _ = await self?.loadDownsampledImage(from: url, maxPixelSize: maxPixelSize, cache: .main)
            }
        }
    }

    func updateThumbnailPrefetchSize(_ maxPixelSize: Int) {
        guard maxPixelSize > 0 else { return }
        if thumbnailPrefetchMaxPixelSize == maxPixelSize {
            return
        }
        thumbnailPrefetchMaxPixelSize = maxPixelSize
        startThumbnailPrefetchIfNeeded()
    }

    private func startThumbnailPrefetchIfNeeded() {
        guard thumbnailPrefetchMaxPixelSize > 0, !images.isEmpty else { return }
        thumbnailPrefetchTask?.cancel()

        let maxPixelSize = thumbnailPrefetchMaxPixelSize
        let imagesToPrefetch = Array(images.prefix(thumbnailCacheLimit))

        thumbnailPrefetchTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            var index = 0
            while index < imagesToPrefetch.count {
                if Task.isCancelled { break }
                let batchEnd = min(index + self.thumbnailPrefetchBatchSize, imagesToPrefetch.count)
                let batch = imagesToPrefetch[index..<batchEnd]
                for image in batch {
                    if Task.isCancelled { break }
                    _ = await self.loadDownsampledImage(from: image.url, maxPixelSize: maxPixelSize, cache: .thumbnail)
                }
                index = batchEnd
                if index < imagesToPrefetch.count {
                    try? await Task.sleep(nanoseconds: self.thumbnailPrefetchBatchDelayNanoseconds)
                }
            }
        }
    }

    private static func downsampleImage(at url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func estimateImageCost(_ image: CGImage) -> Int {
        return image.width * image.height * 4
    }

    func startSlideshow() {
        guard !images.isEmpty else { return }
        isSlideshowRunning = true
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in
            self?.navigateToNext()
        }
    }
    
    func stopSlideshow() {
        isSlideshowRunning = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
    
    func toggleSlideshow() {
        if isSlideshowRunning {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }
    
    func updateSlideshowInterval(_ interval: Double) {
        slideshowInterval = interval
        if isSlideshowRunning {
            stopSlideshow()
            startSlideshow()
        }
        savePreferences()
    }
    
    func setSortOrder(_ order: SortOrder) {
        sortOrder = order
        resortImages()
    }
    
    func updateCustomOrder(_ order: [String]) {
        customOrder = order
        if sortOrder == .custom {
            resortImages()
        }
        savePreferences()
    }
    
    // MARK: - Persistence

    func savePreferences() {
        let preferences = Preferences(
            slideshowInterval: slideshowInterval,
            sortOrder: sortOrder.rawValue,
            customOrder: customOrder,
            lastFolder: selectedFolder?.path
        )
        
        if let encoded = try? JSONEncoder().encode(preferences) {
            preferencesStore.set(encoded, forKey: "ImageBrowserPreferences")
        }
    }

    func loadPreferences() {
        guard let data = preferencesStore.data(forKey: "ImageBrowserPreferences"),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return
        }
        
        slideshowInterval = preferences.slideshowInterval
        sortOrder = SortOrder(rawValue: preferences.sortOrder) ?? .name
        customOrder = preferences.customOrder
        
        if let lastFolderPath = preferences.lastFolder {
            let lastFolderURL = URL(fileURLWithPath: lastFolderPath)
            if fileSystem.fileExists(atPath: lastFolderPath) {
                selectedFolder = lastFolderURL
                loadImages(from: lastFolderURL)
            }
        }
    }

    private func applyTestFolderOverrideIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard let testFolderPath = environment["IMAGEBROWSER_TEST_FOLDER"] else {
            return
        }
        if fileSystem.fileExists(atPath: testFolderPath) {
            let testFolderURL = URL(fileURLWithPath: testFolderPath)
            selectedFolder = testFolderURL
            loadImages(from: testFolderURL)
        }
    }
}

struct Preferences: Codable {
    var slideshowInterval: Double
    var sortOrder: String
    var customOrder: [String]
    var lastFolder: String?
}

struct ImageFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let creationDate: Date
    
    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.url == rhs.url
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
