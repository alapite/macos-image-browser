import XCTest
@testable import ImageBrowser

@MainActor
final class FullscreenWindowControllerTests: XCTestCase {
    func testCoordinator_syncsViewStoreWhenWindowFullscreenNotificationsFire() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let viewStore = ViewStore()
        let fullscreenState = FullscreenStateBox(false)

        let coordinator = FullscreenWindowController.Coordinator(
            notificationCenter: .default,
            isWindowFullscreen: { _ in fullscreenState.value }
        )

        coordinator.updateWindow(window, viewStore: viewStore)
        XCTAssertFalse(viewStore.isFullscreen)

        fullscreenState.value = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertTrue(viewStore.isFullscreen)

        fullscreenState.value = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertFalse(viewStore.isFullscreen)
    }
}

private final class FullscreenStateBox: @unchecked Sendable {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}
