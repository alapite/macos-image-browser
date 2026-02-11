import Foundation
import Combine
import AppKit
import ImageIO

private struct ImageScanResult: Sendable {
    let images: [ImageFile]
    let failedImages: [URL]
}

private final class PrefetchContextStore: @unchecked Sendable {
    private let lock = NSLock()
    private var mainGeneration: UInt64 = 0
    private var thumbnailGeneration: UInt64 = 0

    func advanceMain() {
        lock.lock()
        defer { lock.unlock() }
        mainGeneration &+= 1
    }

    func advanceThumbnail() {
        lock.lock()
        defer { lock.unlock() }
        thumbnailGeneration &+= 1
    }

    func currentMain() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return mainGeneration
    }

    func currentThumbnail() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return thumbnailGeneration
    }

    func isCurrentMain(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return mainGeneration == generation
    }

    func isCurrentThumbnail(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return thumbnailGeneration == generation
    }
}

private actor ImageDirectoryScanner {
    private let fileSystem: FileSystemProviding

    init(fileSystem: FileSystemProviding) {
        self.fileSystem = fileSystem
    }

    func scanImages(in url: URL) -> ImageScanResult {
        var foundImages: [ImageFile] = []
        var failedImages: [URL] = []

        if let enumerator = fileSystem.enumerator(
            at: url,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            while case let fileURL as URL = enumerator.nextObject() {
                if Self.isImageFile(fileURL) {
                    do {
                        let attributes = try fileSystem.attributesOfItem(atPath: fileURL.path)
                        if let creationDate = attributes[.creationDate] as? Date {
                            let imageFile = ImageFile(
                                url: fileURL,
                                name: fileURL.lastPathComponent,
                                creationDate: creationDate
                            )
                            foundImages.append(imageFile)
                        }
                    } catch {
                        failedImages.append(fileURL)
                    }
                }
            }
        }

        return ImageScanResult(images: foundImages, failedImages: failedImages)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

actor ImageDownsamplingPipeline: ImageDownsamplingProviding {
    private let imageLoadQueue = DispatchQueue(label: "ImageBrowser.imageLoad", qos: .userInitiated, attributes: .concurrent)
    private let thumbnailCache = NSCache<NSString, CGImage>()
    private let mainImageCache = NSCache<NSString, CGImage>()

    init(thumbnailLimit: Int) {
        thumbnailCache.totalCostLimit = 1024 * 1024 * 50
        thumbnailCache.countLimit = thumbnailLimit

        mainImageCache.totalCostLimit = 1024 * 1024 * 300
        mainImageCache.countLimit = 50
    }

    func loadImage(from url: URL, maxPixelSize: Int, cache: DownsamplingCacheKind) async -> CGImage? {
        guard maxPixelSize > 0 else { return nil }

        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)"
        let cacheStore = cacheStore(for: cache)
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cacheStore.object(forKey: nsCacheKey) {
            return cachedImage
        }

        let image = await withCheckedContinuation { continuation in
            let fileURL = url
            let pixelSize = maxPixelSize
            imageLoadQueue.async {
                let downsampledImage = Self.downsampleImage(at: fileURL, maxPixelSize: pixelSize)
                continuation.resume(returning: downsampledImage)
            }
        }

        if let image = image {
            let cost = Self.estimateImageCost(image)
            cacheStore.setObject(image, forKey: nsCacheKey, cost: cost)
        }

        return image
    }

    private func cacheStore(for cache: DownsamplingCacheKind) -> NSCache<NSString, CGImage> {
        cache == .thumbnail ? thumbnailCache : mainImageCache
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
        image.width * image.height * 4
    }
}

// Performance characteristics (verified 2026-02-02):
// - Loads ~100 images in ~2-3 seconds (background enumeration)
// - Thumbnail cache provides instant second viewing
// - NSCache evicts under memory pressure (100MB limit, 100 image max)
// - Slideshow transitions at 3s interval are smooth

@MainActor
class AppState: ObservableObject {
    @Published var images: [ImageFile] = []
    @Published var currentImageIndex: Int = 0
    @Published var selectedFolder: URL?
    @Published var isSlideshowRunning: Bool = false
    @Published var slideshowInterval: Double = 3.0 // seconds
    @Published var sortOrder: SortOrder = .name
    @Published var customOrder: [String] = [] // URL keys in custom order (legacy filename keys are supported)
    @Published var failedImages: Set<URL> = []
    @Published var isLoadingImages: Bool = false

    private var slideshowTimer: Timer?
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCacheLimit = 1000
    private var thumbnailPrefetchMaxPixelSize = 0
    private var thumbnailPrefetchTask: Task<Void, Never>?
    private var mainImagePrefetchTask: Task<Void, Never>?
    private let prefetchContextStore = PrefetchContextStore()
    private let thumbnailPrefetchBatchSize = 48
    private let thumbnailPrefetchBatchDelayNanoseconds: UInt64 = 120_000_000
    private let imageScanner: ImageDirectoryScanner
    private let downsamplingPipeline: ImageDownsamplingProviding
    private let fileSystem: FileSystemProviding
    private let preferencesStore: PreferencesStore

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case creationDate = "Creation Date"
        case custom = "Custom Order"
    }
    
    init(
        fileSystem: FileSystemProviding = LocalFileSystem(),
        preferencesStore: PreferencesStore = UserDefaultsPreferencesStore(),
        downsamplingPipeline: ImageDownsamplingProviding? = nil
    ) {
        self.fileSystem = fileSystem
        self.preferencesStore = preferencesStore
        self.imageScanner = ImageDirectoryScanner(fileSystem: fileSystem)
        self.downsamplingPipeline = downsamplingPipeline ?? ImageDownsamplingPipeline(thumbnailLimit: thumbnailCacheLimit)
        loadPreferences()
        applyTestFolderOverrideIfNeeded()
        imageCache.totalCostLimit = 1024 * 1024 * 100  // 100 MB
        imageCache.countLimit = 100  // Max 100 cached images
    }

    func loadImages(from url: URL) {
        selectedFolder = url
        failedImages.removeAll()
        isLoadingImages = true
        replacePrefetchContext(cancelThumbnailPrefetch: true)

        let scanner = imageScanner
        Task { [weak self] in
            guard let self = self else { return }
            let scanResult = await scanner.scanImages(in: url)

            self.failedImages.formUnion(scanResult.failedImages)

            var foundImages = scanResult.images
            self.migrateLegacyCustomOrderIfNeeded(using: foundImages)
            self.sortImages(&foundImages)
            self.images = foundImages
            self.currentImageIndex = 0
            self.isLoadingImages = false
            self.savePreferences()
            self.startThumbnailPrefetchIfNeeded()
        }
    }
    
    func sortImages(_ images: inout [ImageFile]) {
        switch sortOrder {
        case .name:
            images.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .creationDate:
            images.sort { $0.creationDate < $1.creationDate }
        case .custom:
            if !customOrder.isEmpty {
                let customOrderLookup = buildCustomOrderLookup(customOrder)
                images.sort { image1, image2 in
                    let index1 = customOrderIndex(for: image1, using: customOrderLookup)
                    let index2 = customOrderIndex(for: image2, using: customOrderLookup)
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
        replacePrefetchContext(cancelThumbnailPrefetch: false)
    }
    
    func navigateToPrevious() {
        guard !images.isEmpty else { return }
        currentImageIndex = (currentImageIndex - 1 + images.count) % images.count
        replacePrefetchContext(cancelThumbnailPrefetch: false)
    }
    
    func navigateToIndex(_ index: Int) {
        guard index >= 0 && index < images.count else { return }
        currentImageIndex = index
        replacePrefetchContext(cancelThumbnailPrefetch: false)
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
        let pipelineCache: DownsamplingCacheKind = cache == .thumbnail ? .thumbnail : .main
        return await downsamplingPipeline.loadImage(from: url, maxPixelSize: maxPixelSize, cache: pipelineCache)
    }

    func prefetchMainImages(around index: Int, maxPixelSize: Int) {
        guard !images.isEmpty else { return }
        replacePrefetchContext(cancelThumbnailPrefetch: false)

        let neighborIndices = [index - 1, index + 1]
            .filter { $0 >= 0 && $0 < images.count }
        guard !neighborIndices.isEmpty else { return }

        let contextGeneration = prefetchContextStore.currentMain()
        let urlsToPrefetch = neighborIndices.map { images[$0].url }
        let pipeline = downsamplingPipeline
        let contextStore = prefetchContextStore

        mainImagePrefetchTask = Task(priority: .utility) {
            await Self.runMainImagePrefetch(
                urlsToPrefetch,
                maxPixelSize: maxPixelSize,
                contextGeneration: contextGeneration,
                contextStore: contextStore,
                pipeline: pipeline
            )
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
        let urlsToPrefetch = Array(images.prefix(thumbnailCacheLimit).map(\.url))
        let batchSize = thumbnailPrefetchBatchSize
        let batchDelayNanoseconds = thumbnailPrefetchBatchDelayNanoseconds
        let pipeline = downsamplingPipeline
        let contextGeneration = prefetchContextStore.currentThumbnail()
        let contextStore = prefetchContextStore

        thumbnailPrefetchTask = Task(priority: .utility) {
            await Self.runThumbnailPrefetch(
                urlsToPrefetch,
                maxPixelSize: maxPixelSize,
                batchSize: batchSize,
                batchDelayNanoseconds: batchDelayNanoseconds,
                contextGeneration: contextGeneration,
                contextStore: contextStore,
                pipeline: pipeline
            )
        }
    }

    private func replacePrefetchContext(cancelThumbnailPrefetch: Bool) {
        prefetchContextStore.advanceMain()
        mainImagePrefetchTask?.cancel()
        mainImagePrefetchTask = nil
        guard cancelThumbnailPrefetch else { return }
        prefetchContextStore.advanceThumbnail()
        thumbnailPrefetchTask?.cancel()
        thumbnailPrefetchTask = nil
    }

    private nonisolated static func runMainImagePrefetch(
        _ urlsToPrefetch: [URL],
        maxPixelSize: Int,
        contextGeneration: UInt64,
        contextStore: PrefetchContextStore,
        pipeline: ImageDownsamplingProviding
    ) async {
        for url in urlsToPrefetch {
            if Task.isCancelled || !contextStore.isCurrentMain(contextGeneration) {
                return
            }
            _ = await pipeline.loadImage(from: url, maxPixelSize: maxPixelSize, cache: .main)
        }
    }

    private nonisolated static func runThumbnailPrefetch(
        _ urlsToPrefetch: [URL],
        maxPixelSize: Int,
        batchSize: Int,
        batchDelayNanoseconds: UInt64,
        contextGeneration: UInt64,
        contextStore: PrefetchContextStore,
        pipeline: ImageDownsamplingProviding
    ) async {
        var index = 0
        while index < urlsToPrefetch.count {
            if Task.isCancelled || !contextStore.isCurrentThumbnail(contextGeneration) {
                return
            }

            let batchEnd = min(index + batchSize, urlsToPrefetch.count)
            let batch = urlsToPrefetch[index..<batchEnd]
            for url in batch {
                if Task.isCancelled || !contextStore.isCurrentThumbnail(contextGeneration) {
                    return
                }
                _ = await pipeline.loadImage(from: url, maxPixelSize: maxPixelSize, cache: .thumbnail)
            }

            index = batchEnd
            if index < urlsToPrefetch.count {
                try? await Task.sleep(nanoseconds: batchDelayNanoseconds)
            }
        }
    }

    func startSlideshow() {
        guard !images.isEmpty else { return }
        isSlideshowRunning = true
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.navigateToNext()
            }
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
        customOrder = normalizeCustomOrderKeys(order, using: images)
        if sortOrder == .custom {
            resortImages()
        }
        savePreferences()
    }

    private func customOrderKey(for url: URL) -> String {
        url.standardizedFileURL.absoluteString
    }

    private func customOrderKey(for image: ImageFile) -> String {
        customOrderKey(for: image.url)
    }

    private func buildCustomOrderLookup(_ order: [String]) -> [String: Int] {
        var lookup: [String: Int] = [:]
        for (index, key) in order.enumerated() where lookup[key] == nil {
            lookup[key] = index
        }
        return lookup
    }

    private func customOrderIndex(for image: ImageFile, using lookup: [String: Int]) -> Int {
        let urlKey = customOrderKey(for: image)
        if let index = lookup[urlKey] {
            return index
        }

        if let legacyIndex = lookup[image.name] {
            return legacyIndex
        }

        return Int.max
    }

    private func isLegacyCustomOrderKey(_ key: String) -> Bool {
        guard let url = URL(string: key) else { return true }
        return !url.isFileURL
    }

    private func normalizeCustomOrderKeys(_ order: [String], using images: [ImageFile]) -> [String] {
        guard !order.isEmpty else { return [] }
        guard order.contains(where: isLegacyCustomOrderKey) else { return order }

        var keysByName: [String: [String]] = [:]
        for image in images {
            keysByName[image.name, default: []].append(customOrderKey(for: image))
        }

        var normalizedOrder: [String] = []
        for key in order {
            if !isLegacyCustomOrderKey(key) {
                normalizedOrder.append(key)
                continue
            }

            guard var availableKeys = keysByName[key], !availableKeys.isEmpty else {
                continue
            }
            normalizedOrder.append(availableKeys.removeFirst())
            keysByName[key] = availableKeys
        }

        return normalizedOrder.isEmpty ? order : normalizedOrder
    }

    private func migrateLegacyCustomOrderIfNeeded(using images: [ImageFile]) {
        customOrder = normalizeCustomOrderKeys(customOrder, using: images)
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

struct ImageFile: Identifiable, Equatable, Sendable {
    var id: String {
        url.standardizedFileURL.absoluteString
    }
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
