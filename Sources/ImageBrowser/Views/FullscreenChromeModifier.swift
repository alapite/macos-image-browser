import SwiftUI

/// View modifier that manages chrome (toolbar and sidebar) visibility in fullscreen mode
struct FullscreenChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewStore: ViewStore
    @State private var chromeVisible: Bool = true
    @State private var hoverTask: Task<Void, Never>?

    private let edgeThreshold: CGFloat = 20 // 20pt from edge

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .toolbar(chromeVisible ? .visible : .hidden, for: .windowToolbar)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard viewStore.isFullscreen else { return }

                            let isInEdge = isInEdgeArea(value.location, geometry: geometry)

                            handleHover(isInEdge: isInEdge)
                        }
                )
        }
        .onChange(of: viewStore.isFullscreen) { _, newValue in
            withAnimation(MotionPreferenceResolver.standardAnimation(reduceMotion: reduceMotion, duration: 0.2)) {
                chromeVisible = !newValue
            }
        }
    }

    private func isInEdgeArea(_ location: CGPoint, geometry: GeometryProxy) -> Bool {
        let isInTopEdge = location.y <= edgeThreshold
        let isInLeftEdge = location.x <= edgeThreshold
        let isInRightEdge = location.x >= geometry.size.width - edgeThreshold

        return isInTopEdge || isInLeftEdge || isInRightEdge
    }

    private func handleHover(isInEdge: Bool) {
        hoverTask?.cancel()

        if isInEdge && !chromeVisible {
            // Show chrome immediately when hovering near edge
            withAnimation(MotionPreferenceResolver.standardAnimation(reduceMotion: reduceMotion, duration: 0.15)) {
                chromeVisible = true
            }
        } else if !isInEdge && chromeVisible {
            // Delay hiding chrome to avoid flicker
            hoverTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                } catch {
                    return // Task was cancelled
                }

                await MainActor.run {
                    withAnimation(MotionPreferenceResolver.standardAnimation(reduceMotion: reduceMotion, duration: 0.3)) {
                        chromeVisible = false
                    }
                }
            }
        }
    }
}

extension View {
    /// Applies fullscreen chrome behavior (auto-hiding in fullscreen mode)
    func fullscreenChrome(viewStore: ViewStore) -> some View {
        self.modifier(FullscreenChromeModifier(viewStore: viewStore))
    }
}
