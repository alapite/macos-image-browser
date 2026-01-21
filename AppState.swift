import Foundation
import Combine
import AppKit

class AppState: ObservableObject {
    @Published var images: [ImageFile] = []
    @Published var currentImageIndex: Int = 0
    @Published var selectedFolder: URL?
    @Published var isSlideshowRunning: Bool = false
    @Published var slideshowInterval: Double = 3.0 // seconds
    @Published var sortOrder: SortOrder = .name
    @Published var customOrder: [String] = [] // filenames in custom order
    @Published var failedImages: Set<URL> = []
    
    private var slideshowTimer: Timer?
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case creationDate = "Creation Date"
        case custom = "Custom Order"
    }
    
    init() {
        loadPreferences()
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
    
    private func loadImages(from url: URL) {
        failedImages.removeAll()
        var foundImages: [ImageFile] = []
        
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            while case let fileURL as URL = enumerator.nextObject() {
                if isImageFile(fileURL) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                        if let creationDate = attributes[.creationDate] as? Date {
                            let imageFile = ImageFile(
                                url: fileURL,
                                name: fileURL.lastPathComponent,
                                creationDate: creationDate
                            )
                            foundImages.append(imageFile)
                        }
                    } catch {
                        failedImages.insert(fileURL)
                    }
                }
            }
        }
        
        sortImages(&foundImages)
        images = foundImages
        currentImageIndex = 0
        savePreferences()
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
    
    private func savePreferences() {
        let preferences = Preferences(
            slideshowInterval: slideshowInterval,
            sortOrder: sortOrder.rawValue,
            customOrder: customOrder,
            lastFolder: selectedFolder?.path
        )
        
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: "ImageBrowserPreferences")
        }
    }
    
    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: "ImageBrowserPreferences"),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return
        }
        
        slideshowInterval = preferences.slideshowInterval
        sortOrder = SortOrder(rawValue: preferences.sortOrder) ?? .name
        customOrder = preferences.customOrder
        
        if let lastFolderPath = preferences.lastFolder {
            let lastFolderURL = URL(fileURLWithPath: lastFolderPath)
            if FileManager.default.fileExists(atPath: lastFolderPath) {
                selectedFolder = lastFolderURL
                loadImages(from: lastFolderURL)
            }
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
