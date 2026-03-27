import AppKit
import SwiftUI

protocol FolderPickingProviding: Sendable {
    @MainActor
    func pickFolder() -> URL?
}

struct OpenPanelFolderPicker: FolderPickingProviding, Sendable {
    @MainActor
    func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }
}

protocol WindowCommandPerforming: Sendable {
    @MainActor
    func openSettingsWindow()

    @MainActor
    func toggleSidebar()

    @MainActor
    func enterFullscreen()

    @MainActor
    func exitFullscreen()
}

struct AppKitWindowCommands: WindowCommandPerforming, Sendable {
    private let keyWindowProvider: @MainActor @Sendable () -> NSWindow?
    private let isWindowFullscreen: @MainActor @Sendable (NSWindow) -> Bool
    private let toggleFullscreen: @MainActor @Sendable (NSWindow) -> Void
    private let toggleSidebarAction: @MainActor @Sendable () -> Void

    init(
        keyWindowProvider: @escaping @MainActor @Sendable () -> NSWindow? = { NSApp.keyWindow },
        isWindowFullscreen: @escaping @MainActor @Sendable (NSWindow) -> Bool = { window in
            window.styleMask.contains(.fullScreen)
        },
        toggleFullscreen: @escaping @MainActor @Sendable (NSWindow) -> Void = { window in
            window.toggleFullScreen(nil)
        },
        toggleSidebarAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.keyWindowProvider = keyWindowProvider
        self.isWindowFullscreen = isWindowFullscreen
        self.toggleFullscreen = toggleFullscreen
        self.toggleSidebarAction = toggleSidebarAction ?? {
            keyWindowProvider()?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
    }

    @MainActor
    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @MainActor
    func toggleSidebar() {
        toggleSidebarAction()
    }

    @MainActor
    func enterFullscreen() {
        guard let keyWindow = keyWindowProvider(), !isWindowFullscreen(keyWindow) else {
            return
        }

        toggleFullscreen(keyWindow)
    }

    @MainActor
    func exitFullscreen() {
        guard let keyWindow = keyWindowProvider(), isWindowFullscreen(keyWindow) else {
            return
        }

        toggleFullscreen(keyWindow)
    }
}

protocol KeyEventMonitoring: Sendable {
    @MainActor
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any

    @MainActor
    func removeMonitor(_ monitor: Any)
}

struct AppKitKeyEventMonitor: KeyEventMonitoring, Sendable {
    @MainActor
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler) as Any
    }

    @MainActor
    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

struct UIInteractionDependencies: Sendable {
    let folderPicker: FolderPickingProviding
    let windowCommands: WindowCommandPerforming
    let keyEventMonitor: KeyEventMonitoring

    static let live = UIInteractionDependencies(
        folderPicker: OpenPanelFolderPicker(),
        windowCommands: AppKitWindowCommands(),
        keyEventMonitor: AppKitKeyEventMonitor()
    )
}

private struct UIInteractionDependenciesKey: EnvironmentKey {
    static let defaultValue = UIInteractionDependencies.live
}

extension EnvironmentValues {
    var uiInteractionDependencies: UIInteractionDependencies {
        get { self[UIInteractionDependenciesKey.self] }
        set { self[UIInteractionDependenciesKey.self] = newValue }
    }
}
