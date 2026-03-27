import XCTest
@testable import ImageBrowser

@MainActor
final class FilterStoreTests: XCTestCase {

    var filterStore: FilterStore!

    override func setUp() async throws {
        try await super.setUp()
        filterStore = FilterStore()
    }

    override func tearDown() async throws {
        filterStore = nil
        try await super.tearDown()
    }

    // MARK: - File Size Filter Tests

    func testFileSizeFilterEnumCases() throws {
        // Test that FileSizeFilter enum has all expected cases
        // This test will fail until the enum is created
        let allCases: [FilterStore.FileSizeFilter] = [
            .all,
            .small,
            .medium,
            .large,
            .veryLarge
        ]

        XCTAssertEqual(allCases.count, 5, "FileSizeFilter should have 5 cases")
    }

    func testFileSizeFilterActiveCount() throws {
        // Adding file size filter should increment activeFilterCount

        // Initially, no filters active
        XCTAssertEqual(filterStore.activeFilterCount, 0, "No filters should be active initially")

        // Set file size filter to small
        filterStore.fileSizeFilter = .small

        XCTAssertEqual(filterStore.activeFilterCount, 1, "Setting file size filter should increment active count")

        // Reset should clear file size filter
        filterStore.reset()

        XCTAssertEqual(filterStore.activeFilterCount, 0, "Reset should clear file size filter")
    }

    // MARK: - Dimension Filter Tests

    func testDimensionFilterEnumCases() throws {
        // Test that DimensionFilter enum has all expected cases
        let allCases: [FilterStore.DimensionFilter] = [
            .all,
            .landscape,
            .portrait,
            .square
        ]

        XCTAssertEqual(allCases.count, 4, "DimensionFilter should have 4 cases")
    }

    func testDimensionFilterActiveCount() throws {
        // Adding dimension filter should increment activeFilterCount

        // Initially, no filters active
        XCTAssertEqual(filterStore.activeFilterCount, 0, "No filters should be active initially")

        // Set dimension filter to landscape
        filterStore.dimensionFilter = .landscape

        XCTAssertEqual(filterStore.activeFilterCount, 1, "Setting dimension filter should increment active count")

        // Reset should clear dimension filter
        filterStore.reset()

        XCTAssertEqual(filterStore.activeFilterCount, 0, "Reset should clear dimension filter")
    }

    // MARK: - Combined Filter Tests

    func testMultipleFiltersIncrementActiveCount() throws {
        // Test that multiple filters increment activeFilterCount correctly

        // Initially, no filters active
        XCTAssertEqual(filterStore.activeFilterCount, 0, "No filters should be active initially")

        // Set rating filter
        filterStore.minimumRating = 4
        XCTAssertEqual(filterStore.activeFilterCount, 1, "Rating filter should be active")

        // Set file size filter
        filterStore.fileSizeFilter = .medium
        XCTAssertEqual(filterStore.activeFilterCount, 2, "Should have 2 active filters")

        // Set dimension filter
        filterStore.dimensionFilter = .portrait
        XCTAssertEqual(filterStore.activeFilterCount, 3, "Should have 3 active filters")

        // Reset should clear all filters
        filterStore.reset()
        XCTAssertEqual(filterStore.activeFilterCount, 0, "Reset should clear all filters")
    }

    func testResetClearsAllFilters() throws {
        // Test that reset() clears all filters including new ones

        // Set all filters to non-default values
        filterStore.minimumRating = 3
        filterStore.showFavoritesOnly = true
        filterStore.selectedTags = ["nature", "landscape"]
        filterStore.fileSizeFilter = .large
        filterStore.dimensionFilter = .square

        // Verify filters are active
        XCTAssertGreaterThan(filterStore.activeFilterCount, 0, "Filters should be active")

        // Reset
        filterStore.reset()

        // Verify all filters are cleared
        XCTAssertEqual(filterStore.minimumRating, 0, "Rating should be reset to 0")
        XCTAssertFalse(filterStore.showFavoritesOnly, "Favorites should be reset to false")
        XCTAssertTrue(filterStore.selectedTags.isEmpty, "Tags should be empty")
        XCTAssertEqual(filterStore.fileSizeFilter, .all, "File size filter should be reset to .all")
        XCTAssertEqual(filterStore.dimensionFilter, .all, "Dimension filter should be reset to .all")
        XCTAssertEqual(filterStore.activeFilterCount, 0, "No filters should be active after reset")
    }

    func testIsActiveIncludesNewFilters() throws {
        // Test that isActive includes new filters in its calculation

        // Initially, not active
        XCTAssertFalse(filterStore.isActive, "Should not be active initially")

        // Set file size filter
        filterStore.fileSizeFilter = .small
        XCTAssertTrue(filterStore.isActive, "Should be active with file size filter")

        // Reset
        filterStore.reset()
        XCTAssertFalse(filterStore.isActive, "Should not be active after reset")

        // Set dimension filter
        filterStore.dimensionFilter = .portrait
        XCTAssertTrue(filterStore.isActive, "Should be active with dimension filter")
    }
}
