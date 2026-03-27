import AppKit
import SwiftUI

/// AppKit window wrapper that tracks fullscreen state changes
///
/// This view monitors the window's fullscreen state and updates ViewStore accordingly.
/// It uses ObservableObject instead of EnvironmentObject to avoid initialization crashes.
struct FullscreenWindowController: NSViewRepresentable {
    @ObservedObject var viewStore: ViewStore

    func makeNSView(context: Context) -> NSView {
        let view = WindowBindingView()
        view.onWindowChange = { window in
            context.coordinator.updateWindow(window, viewStore: viewStore)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateWindow(nsView.window, viewStore: viewStore)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private let notificationCenter: NotificationCenter
        private let isWindowFullscreen: @Sendable (NSWindow) -> Bool
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []

        init(
            notificationCenter: NotificationCenter = .default,
            isWindowFullscreen: @escaping @Sendable (NSWindow) -> Bool = { window in
                MainActor.assumeIsolated {
                    window.styleMask.contains(.fullScreen)
                }
            }
        ) {
            self.notificationCenter = notificationCenter
            self.isWindowFullscreen = isWindowFullscreen
        }

        deinit {
            removeObservers()
        }

        @MainActor
        func updateWindow(_ window: NSWindow?, viewStore: ViewStore) {
            if observedWindow !== window {
                removeObservers()
                observedWindow = window
                if let window {
                    observeFullscreenNotifications(for: window, viewStore: viewStore)
                }
            }

            guard let window else {
                return
            }

            synchronizeFullscreenState(from: window, viewStore: viewStore)
        }

        @MainActor
        private func synchronizeFullscreenState(from window: NSWindow, viewStore: ViewStore) {
            let isInFullscreen = isWindowFullscreen(window)
            if viewStore.isFullscreen != isInFullscreen {
                viewStore.isFullscreen = isInFullscreen
            }
        }

        private func observeFullscreenNotifications(for window: NSWindow, viewStore: ViewStore) {
            let isWindowFullscreen = self.isWindowFullscreen
            let synchronizeFromNotification: @Sendable (Notification) -> Void = { [weak viewStore] notification in
                guard let viewStore,
                      let notifiedWindow = notification.object as? NSWindow else {
                    return
                }

                let isInFullscreen = isWindowFullscreen(notifiedWindow)
                MainActor.assumeIsolated {
                    if viewStore.isFullscreen != isInFullscreen {
                        viewStore.isFullscreen = isInFullscreen
                    }
                }
            }

            let enterToken = notificationCenter.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { notification in
                synchronizeFromNotification(notification)
            }

            let exitToken = notificationCenter.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { notification in
                synchronizeFromNotification(notification)
            }

            notificationTokens = [enterToken, exitToken]
        }

        private func removeObservers() {
            notificationTokens.forEach(notificationCenter.removeObserver(_:))
            notificationTokens.removeAll()
        }
    }
}

private final class WindowBindingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        onWindowChange?(newWindow)
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        onWindowChange?(nil)
    }
}
