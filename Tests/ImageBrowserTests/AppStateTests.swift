import XCTest
@testable import ImageBrowser

final class AppStateTests: XCTestCase {
    func testSortByNameIsLocalizedCaseInsensitive() {
        let state = AppState()
        state.sortOrder = .name

        var images = [
            makeImageFile(name: "b.JPG", creationDate: makeDate(year: 2020, month: 1, day: 2)),
            makeImageFile(name: "A.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "c.jpg", creationDate: makeDate(year: 2020, month: 1, day: 3)),
        ]

        state.sortImages(&images)

        XCTAssertEqual(images.map(\.name), ["A.jpg", "b.JPG", "c.jpg"])
    }

    func testSortByCreationDateIsAscending() {
        let state = AppState()
        state.sortOrder = .creationDate

        var images = [
            makeImageFile(name: "b.jpg", creationDate: makeDate(year: 2020, month: 1, day: 2)),
            makeImageFile(name: "a.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "c.jpg", creationDate: makeDate(year: 2020, month: 1, day: 3)),
        ]

        state.sortImages(&images)

        XCTAssertEqual(images.map(\.name), ["a.jpg", "b.jpg", "c.jpg"])
    }

    func testSortByCustomOrderRespectsKnownEntriesAndPushesUnknownToEnd() {
        let state = AppState()
        state.sortOrder = .custom
        state.customOrder = ["b.jpg", "a.jpg"]

        var images = [
            makeImageFile(name: "c.jpg", creationDate: makeDate(year: 2020, month: 1, day: 3)),
            makeImageFile(name: "a.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "b.jpg", creationDate: makeDate(year: 2020, month: 1, day: 2)),
        ]

        state.sortImages(&images)

        XCTAssertEqual(images.map(\.name), ["b.jpg", "a.jpg", "c.jpg"])
    }

    func testNavigateToNextWrapsFromLastToFirst() {
        let state = AppState()
        state.images = [
            makeImageFile(name: "a.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "b.jpg", creationDate: makeDate(year: 2020, month: 1, day: 2)),
        ]
        state.currentImageIndex = 1

        state.navigateToNext()

        XCTAssertEqual(state.currentImageIndex, 0)
    }

    func testNavigateToPreviousWrapsFromFirstToLast() {
        let state = AppState()
        state.images = [
            makeImageFile(name: "a.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "b.jpg", creationDate: makeDate(year: 2020, month: 1, day: 2)),
        ]
        state.currentImageIndex = 0

        state.navigateToPrevious()

        XCTAssertEqual(state.currentImageIndex, 1)
    }

    func testNavigateToIndexIgnoresOutOfRangeIndices() {
        let state = AppState()
        state.images = [
            makeImageFile(name: "a.jpg", creationDate: makeDate(year: 2020, month: 1, day: 1)),
            makeImageFile(name: "b.jpg", creationDate: makeDate(year: 2020, month: 1, day: 2)),
        ]
        state.currentImageIndex = 1

        state.navigateToIndex(-1)
        XCTAssertEqual(state.currentImageIndex, 1)

        state.navigateToIndex(2)
        XCTAssertEqual(state.currentImageIndex, 1)
    }
}
