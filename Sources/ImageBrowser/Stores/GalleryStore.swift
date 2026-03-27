import Foundation
import Combine

@MainActor
protocol GalleryImageSource: AnyObject {
    var galleryImages: [ImageFile] { get }
    var galleryFailedImages: Set<URL> { get }
    var galleryUnsupportedImages: Set<URL> { get }
    var galleryCurrentImageIndex: Int { get }
    func navigateToGalleryImage(at index: Int)
    var galleryImagesPublisher: AnyPublisher<Void, Never> { get }
    var galleryFailedImagesPublisher: AnyPublisher<Void, Never> { get }
    var galleryUnsupportedImagesPublisher: AnyPublisher<Void, Never> { get }
    var galleryCurrentImageIndexPublisher: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol GalleryMetadataSource: AnyObject {
    var galleryMetadataImages: [ImageFile] { get }
    var galleryMetadataPublisher: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol GalleryFiltering: AnyObject {
    var galleryIsFilterActive: Bool { get }
    var galleryFilterCriteria: GalleryFilterCriteria { get }
    var galleryFilterChangesPublisher: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol SyncImageTagLookupProviding: AnyObject {
    func tagsForImageSync(_ imageUrl: String) -> Set<String>
    var galleryTagChangesPublisher: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol GalleryCollectionSource: AnyObject {
    var galleryActiveCollection: SmartCollection? { get }
    func filteredImages(for collection: SmartCollection) -> [ImageFile]
    var galleryCollectionChangesPublisher: AnyPublisher<Void, Never> { get }
}

struct DisplayImage: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let creationDate: Date
    let rating: Int
    let isFavorite: Bool
    let isExcluded: Bool
    let excludedAt: Date?
    let fileSizeBytes: Int64
    let fullIndex: Int
    let hasLoadError: Bool
    let isUnsupportedFormat: Bool

    init(
        id: String,
        url: URL,
        name: String,
        creationDate: Date,
        rating: Int,
        isFavorite: Bool,
        isExcluded: Bool = false,
        excludedAt: Date? = nil,
        fileSizeBytes: Int64,
        fullIndex: Int,
        hasLoadError: Bool,
        isUnsupportedFormat: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.creationDate = creationDate
        self.rating = rating
        self.isFavorite = isFavorite
        self.isExcluded = isExcluded
        self.excludedAt = excludedAt
        self.fileSizeBytes = fileSizeBytes
        self.fullIndex = fullIndex
        self.hasLoadError = hasLoadError
        self.isUnsupportedFormat = isUnsupportedFormat
    }
}

struct GallerySnapshot: Sendable {
    let visibleImages: [DisplayImage]
    let fullIndexByID: [String: Int]
    let totalCount: Int
    let filteredCount: Int
    let unfilteredTotalCount: Int
    let subtitle: String
    let activeCollectionName: String?
    let selectedImageID: String?
    let currentDisplayImage: DisplayImage?

    static let empty = GallerySnapshot(
        visibleImages: [],
        fullIndexByID: [:],
        totalCount: 0,
        filteredCount: 0,
        unfilteredTotalCount: 0,
        subtitle: "0 images",
        activeCollectionName: nil,
        selectedImageID: nil,
        currentDisplayImage: nil
    )

    func fullIndex(for imageID: String) -> Int? {
        fullIndexByID[imageID]
    }
}

@MainActor
final class GalleryStore: ObservableObject {
    @Published private(set) var snapshot: GallerySnapshot = .empty

    private let imageSource: GalleryImageSource
    private let metadataSource: GalleryMetadataSource
    private let filtering: GalleryFiltering
    private let tagLookup: SyncImageTagLookupProviding
    private let collectionSource: GalleryCollectionSource?

    private var cancellables: Set<AnyCancellable> = []
    private var recomputeTask: Task<Void, Never>?
    private var recomputeGeneration: UInt64 = 0
    internal private(set) var fullRecomputeCount: Int = 0
    internal private(set) var selectionOnlyUpdateCount: Int = 0

    var excludedImages: [DisplayImage] {
        snapshot.visibleImages.filter { $0.isExcluded }
    }

    init(
        imageSource: GalleryImageSource,
        metadataSource: GalleryMetadataSource,
        filtering: GalleryFiltering,
        tagLookup: SyncImageTagLookupProviding,
        collectionSource: GalleryCollectionSource? = nil
    ) {
        self.imageSource = imageSource
        self.metadataSource = metadataSource
        self.filtering = filtering
        self.tagLookup = tagLookup
        self.collectionSource = collectionSource
        bind()
        scheduleRecompute()
    }

    deinit {
        recomputeTask?.cancel()
    }

    private func bind() {
        imageSource.galleryImagesPublisher
            .sink { [weak self] in
                self?.scheduleRecompute()
            }
            .store(in: &cancellables)

        imageSource.galleryFailedImagesPublisher
            .merge(with: imageSource.galleryUnsupportedImagesPublisher)
            .sink { [weak self] in
                self?.scheduleRecompute()
            }
            .store(in: &cancellables)

        imageSource.galleryCurrentImageIndexPublisher
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateSelectionOnlySnapshot()
                }
            }
            .store(in: &cancellables)

        metadataSource.galleryMetadataPublisher
            .sink { [weak self] in
                self?.scheduleRecompute()
            }
            .store(in: &cancellables)

        if let collectionSource = collectionSource {
            collectionSource.galleryCollectionChangesPublisher
                .sink { [weak self] in
                    self?.scheduleRecompute()
                }
                .store(in: &cancellables)
        }

        Publishers.Merge(
            filtering.galleryFilterChangesPublisher,
            tagLookup.galleryTagChangesPublisher
        )
        .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.scheduleRecompute()
        }
        .store(in: &cancellables)
    }

    private func scheduleRecompute() {
        recomputeGeneration &+= 1
        let currentGeneration = recomputeGeneration

        recomputeTask?.cancel()

        let activeCollection = collectionSource?.galleryActiveCollection
        let useCollectionFilter = activeCollection != nil

        let sourceImages: [ImageFile]
        if let collection = activeCollection {
            sourceImages = collectionSource?.filteredImages(for: collection) ?? []
        } else {
            sourceImages = imageSource.galleryImages
        }

        let failedImages = imageSource.galleryFailedImages
        let unsupportedImages = imageSource.galleryUnsupportedImages
        let currentImageIndex = imageSource.galleryCurrentImageIndex
        let metadataImages = metadataSource.galleryMetadataImages
        let criteria = filtering.galleryFilterCriteria
        let isFilterActive = filtering.galleryIsFilterActive || useCollectionFilter
        let tagsByURL = Dictionary(uniqueKeysWithValues: sourceImages.map { image in
            let imageURL = image.url.standardizedFileURL.absoluteString
            return (imageURL, tagLookup.tagsForImageSync(imageURL))
        })

        recomputeTask = Task(priority: .userInitiated) { [weak self] in
            let computedSnapshot = Self.computeSnapshot(
                images: sourceImages,
                failedImages: failedImages,
                unsupportedImages: unsupportedImages,
                metadataImages: metadataImages,
                tagsByURL: tagsByURL,
                currentImageIndex: currentImageIndex,
                criteria: criteria,
                unfilteredTotalCount: sourceImages.count,
                activeCollectionName: activeCollection?.name,
                isFilterActive: isFilterActive
            )

            if Task.isCancelled {
                return
            }

            await MainActor.run {
                guard let self = self, self.recomputeGeneration == currentGeneration else {
                    return
                }

                self.snapshot = Self.selectionSnapshot(
                    from: computedSnapshot,
                    images: sourceImages,
                    metadataImages: metadataImages,
                    failedImages: failedImages,
                    unsupportedImages: unsupportedImages,
                    currentImageIndex: self.imageSource.galleryCurrentImageIndex
                )
                self.fullRecomputeCount += 1
            }
        }
    }

    private func updateSelectionOnlySnapshot() {
        snapshot = Self.selectionSnapshot(
            from: snapshot,
            images: imageSource.galleryImages,
            metadataImages: metadataSource.galleryMetadataImages,
            failedImages: imageSource.galleryFailedImages,
            unsupportedImages: imageSource.galleryUnsupportedImages,
            currentImageIndex: imageSource.galleryCurrentImageIndex
        )
        selectionOnlyUpdateCount += 1
    }

    func resetInstrumentationCounts() {
        fullRecomputeCount = 0
        selectionOnlyUpdateCount = 0
    }

    private nonisolated static func computeSnapshot(
        images: [ImageFile],
        failedImages: Set<URL>,
        unsupportedImages: Set<URL>,
        metadataImages: [ImageFile],
        tagsByURL: [String: Set<String>],
        currentImageIndex: Int,
        criteria: GalleryFilterCriteria,
        unfilteredTotalCount: Int,
        activeCollectionName: String?,
        isFilterActive: Bool
    ) -> GallerySnapshot {
        let metadataPairs: [(String, ImageMetadata)] = metadataImages.compactMap { metadataImage in
            guard let metadata = metadataImage.metadata else {
                return nil
            }

            return (metadataImage.url.standardizedFileURL.absoluteString, metadata)
        }
        let metadataByURL = Dictionary(uniqueKeysWithValues: metadataPairs)

        let fullIndexByID = Dictionary(uniqueKeysWithValues: images.enumerated().map { index, image in
            (image.id, index)
        })

        var visibleImages: [DisplayImage] = []
        visibleImages.reserveCapacity(images.count)

        var currentDisplayImage: DisplayImage?

        for (index, baseImage) in images.enumerated() {
            let mergedImage = mergedImage(baseImage, metadataByURL: metadataByURL)
            let displayImage = makeDisplayImage(
                from: mergedImage,
                fullIndex: index,
                failedImages: failedImages,
                unsupportedImages: unsupportedImages
            )

            if index == currentImageIndex {
                currentDisplayImage = displayImage
            }

            let imageTags = tagsByURL[mergedImage.url.standardizedFileURL.absoluteString] ?? []
            if matchesFilters(displayImage, imageTags: imageTags, criteria: criteria) {
                visibleImages.append(displayImage)
            }
        }

        let selectedID: String?
        if let currentDisplayImage, visibleImages.contains(where: { $0.id == currentDisplayImage.id }) {
            selectedID = currentDisplayImage.id
        } else {
            selectedID = nil
        }

        let filteredCount = visibleImages.count
        let totalCount = images.count
        let subtitle: String
        if isFilterActive {
            subtitle = "\(filteredCount) image\(filteredCount == 1 ? "" : "s") (filtered from \(unfilteredTotalCount))"
        } else {
            subtitle = "\(unfilteredTotalCount) image\(unfilteredTotalCount == 1 ? "" : "s")"
        }

        return GallerySnapshot(
            visibleImages: visibleImages,
            fullIndexByID: fullIndexByID,
            totalCount: totalCount,
            filteredCount: filteredCount,
            unfilteredTotalCount: unfilteredTotalCount,
            subtitle: subtitle,
            activeCollectionName: activeCollectionName,
            selectedImageID: selectedID,
            currentDisplayImage: currentDisplayImage
        )
    }

    private nonisolated static func selectionSnapshot(
        from snapshot: GallerySnapshot,
        images: [ImageFile],
        metadataImages: [ImageFile],
        failedImages: Set<URL>,
        unsupportedImages: Set<URL>,
        currentImageIndex: Int
    ) -> GallerySnapshot {
        let metadataPairs: [(String, ImageMetadata)] = metadataImages.compactMap { metadataImage in
            guard let metadata = metadataImage.metadata else {
                return nil
            }

            return (metadataImage.url.standardizedFileURL.absoluteString, metadata)
        }
        let metadataByURL = Dictionary(uniqueKeysWithValues: metadataPairs)

        let currentDisplayImage: DisplayImage?
        if let currentImage = images[safe: currentImageIndex] {
            let mergedImage = mergedImage(currentImage, metadataByURL: metadataByURL)
            currentDisplayImage = makeDisplayImage(
                from: mergedImage,
                fullIndex: currentImageIndex,
                failedImages: failedImages,
                unsupportedImages: unsupportedImages
            )
        } else {
            currentDisplayImage = nil
        }

        let selectedImageID: String?
        if let currentDisplayImage,
           snapshot.visibleImages.contains(where: { $0.id == currentDisplayImage.id }) {
            selectedImageID = currentDisplayImage.id
        } else {
            selectedImageID = nil
        }

        return GallerySnapshot(
            visibleImages: snapshot.visibleImages,
            fullIndexByID: snapshot.fullIndexByID,
            totalCount: snapshot.totalCount,
            filteredCount: snapshot.filteredCount,
            unfilteredTotalCount: snapshot.unfilteredTotalCount,
            subtitle: snapshot.subtitle,
            activeCollectionName: snapshot.activeCollectionName,
            selectedImageID: selectedImageID,
            currentDisplayImage: currentDisplayImage
        )
    }

    private nonisolated static func mergedImage(
        _ image: ImageFile,
        metadataByURL: [String: ImageMetadata]
    ) -> ImageFile {
        guard let metadata = metadataByURL[image.url.standardizedFileURL.absoluteString] else {
            return image
        }

        var updatedImage = image
        updatedImage.metadata = metadata
        return updatedImage
    }

    private nonisolated static func makeDisplayImage(
        from image: ImageFile,
        fullIndex: Int,
        failedImages: Set<URL>,
        unsupportedImages: Set<URL>
    ) -> DisplayImage {
        DisplayImage(
            id: image.id,
            url: image.url,
            name: image.name,
            creationDate: image.creationDate,
            rating: image.rating,
            isFavorite: image.isFavorite,
            isExcluded: image.isExcluded,
            excludedAt: image.metadata?.excludedAt,
            fileSizeBytes: image.fileSizeBytes,
            fullIndex: fullIndex,
            hasLoadError: failedImages.contains(image.url),
            isUnsupportedFormat: unsupportedImages.contains(image.url)
        )
    }

    func selectImage(at fullIndex: Int) {
        guard fullIndex >= 0 && fullIndex < imageSource.galleryImages.count else {
            return
        }

        imageSource.navigateToGalleryImage(at: fullIndex)
    }

    private nonisolated static func matchesFilters(
        _ image: DisplayImage,
        imageTags: Set<String>,
        criteria: GalleryFilterCriteria
    ) -> Bool {
        if criteria.minimumRating > 0 && image.rating < criteria.minimumRating {
            return false
        }

        if criteria.showFavoritesOnly && !image.isFavorite {
            return false
        }

        if let dateRange = criteria.dateRange, !dateRange.contains(image.creationDate) {
            return false
        }

        if !criteria.selectedTags.isEmpty && !criteria.selectedTags.isSubset(of: imageTags) {
            return false
        }

        switch criteria.fileSizeFilter {
        case .all:
            break
        case .small:
            if image.fileSizeBytes >= 2_000_000 { return false }
        case .medium:
            if image.fileSizeBytes < 2_000_000 || image.fileSizeBytes >= 10_000_000 { return false }
        case .large:
            if image.fileSizeBytes < 10_000_000 || image.fileSizeBytes >= 50_000_000 { return false }
        case .veryLarge:
            if image.fileSizeBytes < 50_000_000 { return false }
        }

        return true
    }
}

struct GalleryFilterCriteria: Sendable {
    let minimumRating: Int
    let showFavoritesOnly: Bool
    let selectedTags: Set<String>
    let dateRange: ClosedRange<Date>?
    let fileSizeFilter: FilterStore.FileSizeFilter

    init(
        minimumRating: Int,
        showFavoritesOnly: Bool,
        selectedTags: Set<String>,
        dateRange: ClosedRange<Date>?,
        fileSizeFilter: FilterStore.FileSizeFilter
    ) {
        self.minimumRating = minimumRating
        self.showFavoritesOnly = showFavoritesOnly
        self.selectedTags = selectedTags
        self.dateRange = dateRange
        self.fileSizeFilter = fileSizeFilter
    }
}

@MainActor
extension AppState: GalleryImageSource {
    var galleryImages: [ImageFile] { images }
    var galleryFailedImages: Set<URL> { failedImages }
    var galleryUnsupportedImages: Set<URL> { unsupportedImages }
    var galleryCurrentImageIndex: Int { currentImageIndex }
    func navigateToGalleryImage(at index: Int) { navigateToIndex(index) }
    var galleryImagesPublisher: AnyPublisher<Void, Never> { $images.map { _ in () }.eraseToAnyPublisher() }
    var galleryFailedImagesPublisher: AnyPublisher<Void, Never> { $failedImages.map { _ in () }.eraseToAnyPublisher() }
    var galleryUnsupportedImagesPublisher: AnyPublisher<Void, Never> { $unsupportedImages.map { _ in () }.eraseToAnyPublisher() }
    var galleryCurrentImageIndexPublisher: AnyPublisher<Void, Never> { $currentImageIndex.map { _ in () }.eraseToAnyPublisher() }
}

@MainActor
extension ImageStore: GalleryMetadataSource {
    var galleryMetadataImages: [ImageFile] { images }
    var galleryMetadataPublisher: AnyPublisher<Void, Never> { $images.map { _ in () }.eraseToAnyPublisher() }
}

@MainActor
extension FilterStore: GalleryFiltering {
    var galleryIsFilterActive: Bool { isActive }
    var galleryFilterCriteria: GalleryFilterCriteria {
        GalleryFilterCriteria(
            minimumRating: minimumRating,
            showFavoritesOnly: showFavoritesOnly,
            selectedTags: selectedTags,
            dateRange: dateRange,
            fileSizeFilter: fileSizeFilter
        )
    }
    var galleryFilterChangesPublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            $minimumRating.map { _ in () }.eraseToAnyPublisher(),
            $showFavoritesOnly.map { _ in () }.eraseToAnyPublisher(),
            $selectedTags.map { _ in () }.eraseToAnyPublisher(),
            $dateRange.map { _ in () }.eraseToAnyPublisher(),
            $fileSizeFilter.map { _ in () }.eraseToAnyPublisher(),
            $dimensionFilter.map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }
}

@MainActor
extension TagStore: SyncImageTagLookupProviding {
    var galleryTagChangesPublisher: AnyPublisher<Void, Never> {
        $imageTagsVersion.map { _ in () }.eraseToAnyPublisher()
    }
}

@MainActor
extension CollectionStore: GalleryCollectionSource {
    var galleryActiveCollection: SmartCollection? { activeCollection }
    var galleryCollectionChangesPublisher: AnyPublisher<Void, Never> {
        Publishers.Merge(
            $activeCollection.map { _ in () }.eraseToAnyPublisher(),
            $collections.map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }
}
