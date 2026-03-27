import AppKit
import XCTest
@testable import ImageBrowser

@MainActor
final class KeyEventHandlingCoordinatorTests: XCTestCase {
    func testEscapeKeyIsNotConsumedWhenFullscreenStateIsTrue() throws {
        let keyEventMonitor = RecordingKeyEventMonitor()
        let viewStore = ViewStore()
        viewStore.enterFullscreen()

        let coordinator = KeyEventHandlingView.Coordinator(
            isSlideshowRunning: false,
            viewStore: viewStore,
            onNavigatePrevious: {},
            onNavigateNext: {},
            onRatingShortcut: nil,
            keyEventMonitor: keyEventMonitor
        )

        coordinator.startMonitoring()
        defer { coordinator.stopMonitoring() }

        let escapeEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )

        let handledEvent = keyEventMonitor.send(escapeEvent)

        XCTAssertNotNil(handledEvent, "Esc should pass through to native cancel/dismiss handlers")
        XCTAssertTrue(viewStore.isFullscreen, "Esc monitor must not force fullscreen state transitions")
    }

    func testArrowNavigationPolicy_leftAndRightAreHandledWhenTableViewHasFocus() {
        let tableView = NSTableView()

        XCTAssertTrue(
            KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                keyCode: 123,
                modifierFlags: [],
                firstResponder: tableView
            ),
            "Left arrow should continue navigating images when sidebar table has focus"
        )
        XCTAssertTrue(
            KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                keyCode: 124,
                modifierFlags: [],
                firstResponder: tableView
            ),
            "Right arrow should continue navigating images when sidebar table has focus"
        )
    }

    func testArrowNavigationPolicy_upAndDownAreNotHandledWhenTableViewHasFocus() {
        let tableView = NSTableView()

        XCTAssertFalse(
            KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                keyCode: 126,
                modifierFlags: [],
                firstResponder: tableView
            ),
            "Up arrow should remain available for native table selection movement"
        )
        XCTAssertFalse(
            KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                keyCode: 125,
                modifierFlags: [],
                firstResponder: tableView
            ),
            "Down arrow should remain available for native table selection movement"
        )
    }

    func testArrowNavigationPolicy_doesNotHandleArrowsWhenTextInputHasFocus() {
        let editor = NSTextView()

        XCTAssertFalse(
            KeyEventNavigationPolicy.shouldHandleArrowNavigation(
                keyCode: 123,
                modifierFlags: [],
                firstResponder: editor
            )
        )
    }
}

@MainActor
private final class RecordingKeyEventMonitor: KeyEventMonitoring, @unchecked Sendable {
    private var handler: ((NSEvent) -> NSEvent?)?

    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        self.handler = handler
        return UUID()
    }

    func removeMonitor(_ monitor: Any) {
        handler = nil
    }

    func send(_ event: NSEvent) -> NSEvent? {
        handler?(event)
    }
}
