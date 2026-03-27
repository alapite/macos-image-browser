import XCTest
@testable import ImageBrowser

final class RatingInteractionStateTests: XCTestCase {
    func testDisplayRating_returnsPendingValueImmediatelyAfterFirstClick() {
        var state = RatingInteractionState()

        let generation = state.recordPending(imageID: "image-1", rating: 4)

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(state.displayRating(for: "image-1", persistedRating: 0), 4)
    }

    func testCompleteRequest_ignoresOutOfOrderCompletionForOlderGeneration() {
        var state = RatingInteractionState()

        let firstGeneration = state.recordPending(imageID: "image-1", rating: 2)
        let secondGeneration = state.recordPending(imageID: "image-1", rating: 5)

        XCTAssertFalse(
            state.completeRequest(imageID: "image-1", generation: firstGeneration, didSucceed: true)
        )

        XCTAssertEqual(secondGeneration, firstGeneration + 1)
        XCTAssertEqual(state.displayRating(for: "image-1", persistedRating: 0), 5)
    }

    func testCompleteRequest_failedLatestWriteClearsPendingWithoutRevertingToOlderPendingValue() {
        var state = RatingInteractionState()

        let firstGeneration = state.recordPending(imageID: "image-1", rating: 1)
        let secondGeneration = state.recordPending(imageID: "image-1", rating: 4)

        XCTAssertFalse(
            state.completeRequest(imageID: "image-1", generation: firstGeneration, didSucceed: false)
        )
        XCTAssertEqual(state.displayRating(for: "image-1", persistedRating: 3), 4)

        XCTAssertTrue(
            state.completeRequest(imageID: "image-1", generation: secondGeneration, didSucceed: false)
        )
        XCTAssertEqual(state.displayRating(for: "image-1", persistedRating: 3), 3)
    }
}
