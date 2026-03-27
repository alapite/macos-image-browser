import XCTest
@testable import ImageBrowser

final class SidebarStatusFormatterTests: XCTestCase {
    func testFormatStatus_withActiveCollection_includesCollectionNameAndCounts() {
        let status = SidebarStatusFormatter.formatStatus(
            activeCollectionName: "Favorites",
            filteredCount: 7,
            unfilteredTotalCount: 42,
            isFilteringActive: true
        )

        XCTAssertEqual(status, "Collection: Favorites · 7 images (filtered from 42)")
    }

    func testFormatStatus_withoutActiveCollectionAndWithFilters_showsFilteredCountsOnly() {
        let status = SidebarStatusFormatter.formatStatus(
            activeCollectionName: nil,
            filteredCount: 1,
            unfilteredTotalCount: 42,
            isFilteringActive: true
        )

        XCTAssertEqual(status, "1 image (filtered from 42)")
    }

    func testFormatStatus_withoutActiveCollectionOrFilters_showsTotalOnly() {
        let status = SidebarStatusFormatter.formatStatus(
            activeCollectionName: nil,
            filteredCount: 42,
            unfilteredTotalCount: 42,
            isFilteringActive: false
        )

        XCTAssertEqual(status, "42 images")
    }
}
