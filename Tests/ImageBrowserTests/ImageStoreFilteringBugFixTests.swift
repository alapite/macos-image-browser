import XCTest
@testable import ImageBrowser
import GRDB

/// Tests for bug fix: Only 8 images visible even with no filters
///
/// Regression-oriented tests for filtering defaults and behavior.
@MainActor
final class ImageStoreFilteringBugFixTests: XCTestCase {

    var imageStore: ImageStore!
    var filterStore: FilterStore!
    var dbPool: DatabasePool!

    override func setUp() async throws {
        // Create an in-memory database for testing
        let dbPath = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)

        filterStore = FilterStore()
        imageStore = ImageStore(dbPool: dbPool!, filtering: filterStore!)
    }

    override func tearDown() async throws {
        imageStore = nil
        filterStore = nil
        dbPool = nil
    }

    // MARK: - Filtering Behavior

    /// Test: When ImageStore has 8 images and no active filters,
    /// filteredImages should return all 8 (not fewer).
    func test_filteredImagesReturnsAllImagesWhenNoFiltersActive() async throws {
        // Given: 8 images in ImageStore (from database)
        let testImages = (0..<8).map { index in
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/image\(index).jpg"),
                name: "image\(index).jpg",
                creationDate: Date()
            )
        }

        // Simulate database observation populating ImageStore.images
        imageStore.images = testImages

        // When: No filters are active
        filterStore.minimumRating = 0
        filterStore.showFavoritesOnly = false
        filterStore.dateRange = nil
        filterStore.fileSizeFilter = .all
        filterStore.dimensionFilter = .all

        // Then: filteredImages should return all 8 images
        let filtered = imageStore.filteredImages

        // BUG: This will fail if filteredImages returns < 8
        XCTAssertEqual(filtered.count, 8, "When no filters active, all images in ImageStore should be visible")
    }

    /// Test: When dateRange filter is nil (disabled), it should not filter any images
    ///
    /// This checks that the date filter doesn't have a default value that
    /// accidentally filters out images.
    func test_dateRangeNilDoesNotFilterImages() async throws {
        // Given: 20 images with dates spread across 30 days
        let calendar = Calendar.current
        let today = Date()
        let testImages = (0..<20).compactMap { index -> ImageFile? in
            let date = calendar.date(byAdding: .day, value: -index, to: today) ?? today
            return ImageFile(
                url: URL(fileURLWithPath: "/tmp/image\(index).jpg"),
                name: "image\(index).jpg",
                creationDate: date
            )
        }

        imageStore.images = testImages
        filterStore.dateRange = nil  // Explicitly set to nil (no date filter)

        // When: No date filter applied
        let filtered = imageStore.filteredImages

        // Then: All 20 images should pass through
        XCTAssertEqual(filtered.count, 20, "Nil dateRange should not filter any images")
    }

    /// Test: Verify FilterStore defaults don't accidentally activate filters
    ///
    /// This ensures that on app launch, with default FilterStore values,
    /// no images are filtered out.
    func test_filterStoreDefaultsAreAllDisabled() async throws {
        // Given: Fresh FilterStore with default values
        let freshFilterStore = FilterStore()

        // Then: All filters should be disabled by default
        XCTAssertEqual(freshFilterStore.minimumRating, 0, "Rating filter should default to 0 (disabled)")
        XCTAssertEqual(freshFilterStore.showFavoritesOnly, false, "Favorites filter should default to false")
        XCTAssertTrue(freshFilterStore.selectedTags.isEmpty, "Tags should be empty by default")
        XCTAssertNil(freshFilterStore.dateRange, "Date range should default to nil (disabled)")
        XCTAssertEqual(freshFilterStore.fileSizeFilter, .all, "File size filter should default to .all")
        XCTAssertEqual(freshFilterStore.dimensionFilter, .all, "Dimension filter should default to .all")
        XCTAssertEqual(freshFilterStore.activeFilterCount, 0, "No filters should be active by default")
        XCTAssertFalse(freshFilterStore.isActive, "FilterStore should not be active by default")
    }
}
