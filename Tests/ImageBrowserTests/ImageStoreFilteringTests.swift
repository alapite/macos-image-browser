import XCTest
@testable import ImageBrowser
import GRDB

@MainActor
final class ImageStoreFilteringTests: XCTestCase {

    var imageStore: ImageStore!
    var filterStore: FilterStore!

    override func setUp() async throws {
        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // Delete existing database if present
        try? FileManager.default.removeItem(at: dbPath)

        // Create database pool
        let dbPool = try DatabasePool(path: dbPath.path)

        // Create stores
        filterStore = FilterStore()
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore)
    }

    override func tearDown() async throws {
        imageStore = nil
        filterStore = nil
    }

    // MARK: - No Filter Tests

    func testFilteredImagesReturnsAllImagesWhenNoFiltersActive() throws {
        // Given: Multiple images in the store
        let image1 = createTestImage(name: "image1.jpg", rating: 0, isFavorite: false)
        let image2 = createTestImage(name: "image2.jpg", rating: 5, isFavorite: true)
        let image3 = createTestImage(name: "image3.jpg", rating: 3, isFavorite: false)

        imageStore.images = [image1, image2, image3]

        // When: No filters are active
        XCTAssertFalse(filterStore.isActive, "No filters should be active")

        // Then: All images should be returned
        XCTAssertEqual(imageStore.filteredImages.count, 3, "All images should be returned when no filters active")
        XCTAssertTrue(imageStore.filteredImages.contains(image1), "Should contain image1")
        XCTAssertTrue(imageStore.filteredImages.contains(image2), "Should contain image2")
        XCTAssertTrue(imageStore.filteredImages.contains(image3), "Should contain image3")
    }

    // MARK: - Rating Filter Tests

    func testFilteredImagesAppliesMinimumRatingFilter() throws {
        // Given: Images with different ratings
        let image1 = createTestImage(name: "image1.jpg", rating: 1, isFavorite: false)
        let image2 = createTestImage(name: "image2.jpg", rating: 3, isFavorite: false)
        let image3 = createTestImage(name: "image3.jpg", rating: 5, isFavorite: false)

        imageStore.images = [image1, image2, image3]

        // When: Minimum rating is set to 4
        filterStore.minimumRating = 4

        // Then: Only images with rating >= 4 should be returned
        XCTAssertEqual(imageStore.filteredImages.count, 1, "Only 5-star image should pass filter")
        XCTAssertTrue(imageStore.filteredImages.contains(image3), "Should contain image3 (5 stars)")
        XCTAssertFalse(imageStore.filteredImages.contains(image1), "Should not contain image1 (1 star)")
        XCTAssertFalse(imageStore.filteredImages.contains(image2), "Should not contain image2 (3 stars)")
    }

    // MARK: - Favorites Filter Tests

    func testFilteredImagesAppliesFavoritesOnlyFilter() throws {
        // Given: Mix of favorite and non-favorite images
        let image1 = createTestImage(name: "image1.jpg", rating: 0, isFavorite: false)
        let image2 = createTestImage(name: "image2.jpg", rating: 0, isFavorite: true)
        let image3 = createTestImage(name: "image3.jpg", rating: 0, isFavorite: true)

        imageStore.images = [image1, image2, image3]

        // When: Favorites filter is enabled
        filterStore.showFavoritesOnly = true

        // Then: Only favorite images should be returned
        XCTAssertEqual(imageStore.filteredImages.count, 2, "Only favorites should be returned")
        XCTAssertTrue(imageStore.filteredImages.contains(image2), "Should contain favorite image2")
        XCTAssertTrue(imageStore.filteredImages.contains(image3), "Should contain favorite image3")
        XCTAssertFalse(imageStore.filteredImages.contains(image1), "Should not contain non-favorite image1")
    }

    // MARK: - Date Range Filter Tests

    func testFilteredImagesAppliesDateRangeFilter() throws {
        // Given: Images from different dates
        let dateFormatter = ISO8601DateFormatter()

        let date1 = dateFormatter.date(from: "2024-01-01T00:00:00Z")!
        let date2 = dateFormatter.date(from: "2024-06-15T00:00:00Z")!
        let date3 = dateFormatter.date(from: "2024-12-31T00:00:00Z")!

        let image1 = createTestImage(name: "image1.jpg", rating: 0, isFavorite: false, creationDate: date1)
        let image2 = createTestImage(name: "image2.jpg", rating: 0, isFavorite: false, creationDate: date2)
        let image3 = createTestImage(name: "image3.jpg", rating: 0, isFavorite: false, creationDate: date3)

        imageStore.images = [image1, image2, image3]

        // When: Date range is set to June 2024
        let startDate = dateFormatter.date(from: "2024-06-01T00:00:00Z")!
        let endDate = dateFormatter.date(from: "2024-06-30T23:59:59Z")!
        filterStore.dateRange = startDate...endDate

        // Then: Only images within date range should be returned
        XCTAssertEqual(imageStore.filteredImages.count, 1, "Only June image should pass filter")
        XCTAssertTrue(imageStore.filteredImages.contains(image2), "Should contain image2 (June)")
        XCTAssertFalse(imageStore.filteredImages.contains(image1), "Should not contain image1 (January)")
        XCTAssertFalse(imageStore.filteredImages.contains(image3), "Should not contain image3 (December)")
    }

    // MARK: - Combined Filters Tests

    func testFilteredImagesCombinesFiltersWithANDLogic() throws {
        // Given: Mix of images with different ratings and favorite status
        let image1 = createTestImage(name: "image1.jpg", rating: 5, isFavorite: true)   // Passes both
        let image2 = createTestImage(name: "image2.jpg", rating: 5, isFavorite: false)  // Fails favorite
        let image3 = createTestImage(name: "image3.jpg", rating: 2, isFavorite: true)   // Fails rating

        imageStore.images = [image1, image2, image3]

        // When: Both rating and favorites filters are active
        filterStore.minimumRating = 4
        filterStore.showFavoritesOnly = true

        // Then: Only images matching BOTH filters should be returned
        XCTAssertEqual(imageStore.filteredImages.count, 1, "Only image1 should pass both filters")
        XCTAssertTrue(imageStore.filteredImages.contains(image1), "Should contain image1")
        XCTAssertFalse(imageStore.filteredImages.contains(image2), "Should not contain image2 (not favorite)")
        XCTAssertFalse(imageStore.filteredImages.contains(image3), "Should not contain image3 (rating too low)")
    }

    func testFilteredImagesHandlesImagesWithNilMetadata() throws {
        // Given: Images with and without metadata
        let image1 = createTestImage(name: "image1.jpg", rating: 5, isFavorite: true)   // Has metadata
        let image2 = ImageFile(url: URL(fileURLWithPath: "/tmp/image2.jpg"), name: "image2.jpg", creationDate: Date(), metadata: nil)  // No metadata

        imageStore.images = [image1, image2]

        // When: Rating filter is active
        filterStore.minimumRating = 4

        // Then: Should handle nil metadata gracefully (rating defaults to 0)
        XCTAssertEqual(imageStore.filteredImages.count, 1, "Only image1 should pass rating filter")
        XCTAssertTrue(imageStore.filteredImages.contains(image1), "Should contain image1")
        XCTAssertFalse(imageStore.filteredImages.contains(image2), "Should not contain image2 (no metadata, rating defaults to 0)")
    }

    // MARK: - Helper Methods

    private func createTestImage(name: String, rating: Int, isFavorite: Bool, creationDate: Date? = nil) -> ImageFile {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        let date = creationDate ?? Date()
        let metadata = ImageMetadata(rating: rating, isFavorite: isFavorite)
        return ImageFile(url: url, name: name, creationDate: date, metadata: metadata)
    }
}
