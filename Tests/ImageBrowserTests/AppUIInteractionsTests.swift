import XCTest
@testable import ImageBrowser

@MainActor
final class AppUIInteractionsTests: XCTestCase {
    func testUIInteractionDependencies_isSendable() {
        let dependencies = UIInteractionDependencies(
            folderPicker: TestFolderPicker(),
            windowCommands: TestWindowCommands(),
            keyEventMonitor: TestKeyEventMonitor()
        )

        assertSendable(dependencies)
    }

    func testEnterFullscreen_togglesWindowWhenNotFullscreen() {
        let window = RecordingFullscreenWindow()

        let commands = AppKitWindowCommands(
            keyWindowProvider: { window },
            isWindowFullscreen: { _ in false }
        )

        commands.enterFullscreen()

        XCTAssertEqual(window.toggleFullscreenCallCount, 1)
    }

    func testEnterFullscreen_doesNotToggleWhenAlreadyFullscreen() {
        let window = RecordingFullscreenWindow()

        let commands = AppKitWindowCommands(
            keyWindowProvider: { window },
            isWindowFullscreen: { _ in true }
        )

        commands.enterFullscreen()

        XCTAssertEqual(window.toggleFullscreenCallCount, 0)
    }

    func testExitFullscreen_togglesWindowWhenFullscreen() {
        let window = RecordingFullscreenWindow()

        let commands = AppKitWindowCommands(
            keyWindowProvider: { window },
            isWindowFullscreen: { _ in true }
        )

        commands.exitFullscreen()

        XCTAssertEqual(window.toggleFullscreenCallCount, 1)
    }

    func testExitFullscreen_doesNotToggleWhenAlreadyWindowed() {
        let window = RecordingFullscreenWindow()

        let commands = AppKitWindowCommands(
            keyWindowProvider: { window },
            isWindowFullscreen: { _ in false }
        )

        commands.exitFullscreen()

        XCTAssertEqual(window.toggleFullscreenCallCount, 0)
    }

    func testToggleSidebar_invokesConfiguredSidebarAction() {
        var callCount = 0

        let commands = AppKitWindowCommands(
            toggleSidebarAction: {
                callCount += 1
            }
        )

        commands.toggleSidebar()

        XCTAssertEqual(callCount, 1)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private struct TestFolderPicker: FolderPickingProviding, Sendable {
    @MainActor
    func pickFolder() -> URL? {
        nil
    }
}

private struct TestWindowCommands: WindowCommandPerforming, Sendable {
    @MainActor
    func openSettingsWindow() {}

    @MainActor
    func toggleSidebar() {}

    @MainActor
    func enterFullscreen() {}

    @MainActor
    func exitFullscreen() {}
}

private struct TestKeyEventMonitor: KeyEventMonitoring, Sendable {
    @MainActor
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        UUID()
    }

    @MainActor
    func removeMonitor(_ monitor: Any) {}
}

@MainActor
private final class RecordingFullscreenWindow: NSWindow {
    private(set) var toggleFullscreenCallCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override func toggleFullScreen(_ sender: Any?) {
        toggleFullscreenCallCount += 1
    }
}
