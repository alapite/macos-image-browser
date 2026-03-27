import XCTest
@testable import ImageBrowser

@MainActor
final class ViewStoreFullscreenTests: XCTestCase {

    var viewStore: ViewStore!

    override func setUp() async throws {
        viewStore = ViewStore()
    }

    override func tearDown() async throws {
        viewStore = nil
    }

    // MARK: - Initial State Tests

    func test_isFullscreen_initiallyFalse() {
        // Then
        XCTAssertFalse(viewStore.isFullscreen, "isFullscreen should be false initially")
    }

    // MARK: - Enter Fullscreen Tests

    func test_enterFullscreen_setsIsFullscreenToTrue() {
        // When
        viewStore.enterFullscreen()

        // Then
        XCTAssertTrue(viewStore.isFullscreen, "isFullscreen should be true after entering fullscreen")
    }

    func test_enterFullscreen_whenAlreadyFullscreen_remainsTrue() {
        // Given
        viewStore.enterFullscreen()

        // When
        viewStore.enterFullscreen()

        // Then
        XCTAssertTrue(viewStore.isFullscreen, "isFullscreen should remain true when already in fullscreen")
    }

    // MARK: - Exit Fullscreen Tests

    func test_exitFullscreen_setsIsFullscreenToFalse() {
        // Given
        viewStore.enterFullscreen()

        // When
        viewStore.exitFullscreen()

        // Then
        XCTAssertFalse(viewStore.isFullscreen, "isFullscreen should be false after exiting fullscreen")
    }

    func test_exitFullscreen_whenNotFullscreen_remainsFalse() {
        // Given
        viewStore.exitFullscreen()

        // When
        viewStore.exitFullscreen()

        // Then
        XCTAssertFalse(viewStore.isFullscreen, "isFullscreen should remain false when not in fullscreen")
    }

    // MARK: - Toggle Fullscreen Tests

    func test_toggleFullscreen_fromFalse_setsToTrue() {
        // Given
        XCTAssertFalse(viewStore.isFullscreen, "isFullscreen should start as false")

        // When
        viewStore.toggleFullscreen()

        // Then
        XCTAssertTrue(viewStore.isFullscreen, "isFullscreen should be true after toggle from false")
    }

    func test_toggleFullscreen_fromTrue_setsToFalse() {
        // Given
        viewStore.enterFullscreen()
        XCTAssertTrue(viewStore.isFullscreen, "isFullscreen should be true")

        // When
        viewStore.toggleFullscreen()

        // Then
        XCTAssertFalse(viewStore.isFullscreen, "isFullscreen should be false after toggle from true")
    }

    func test_toggleFullscreen_multipleTimes_alternates() {
        // Given
        XCTAssertFalse(viewStore.isFullscreen)

        // When & Then
        viewStore.toggleFullscreen()
        XCTAssertTrue(viewStore.isFullscreen, "Toggle 1: should be true")

        viewStore.toggleFullscreen()
        XCTAssertFalse(viewStore.isFullscreen, "Toggle 2: should be false")

        viewStore.toggleFullscreen()
        XCTAssertTrue(viewStore.isFullscreen, "Toggle 3: should be true")

        viewStore.toggleFullscreen()
        XCTAssertFalse(viewStore.isFullscreen, "Toggle 4: should be false")
    }
}
