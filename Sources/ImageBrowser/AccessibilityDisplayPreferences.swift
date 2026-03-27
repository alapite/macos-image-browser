import SwiftUI

struct ViewerBackgroundVisualStyle: Equatable {
    let usesSolidBackground: Bool
    let gradientTopOpacity: Double
    let gradientBottomOpacity: Double
    let radialHighlightOpacity: Double
}

enum ViewerBackgroundVisualStyleResolver {
    static func resolve(
        reduceTransparency: Bool,
        colorContrast: ColorSchemeContrast
    ) -> ViewerBackgroundVisualStyle {
        guard !reduceTransparency else {
            return ViewerBackgroundVisualStyle(
                usesSolidBackground: true,
                gradientTopOpacity: 1.0,
                gradientBottomOpacity: 1.0,
                radialHighlightOpacity: 0.0
            )
        }

        let highlightOpacity: Double = colorContrast == .increased ? 0.35 : 0.6

        return ViewerBackgroundVisualStyle(
            usesSolidBackground: false,
            gradientTopOpacity: 0.92,
            gradientBottomOpacity: 0.98,
            radialHighlightOpacity: highlightOpacity
        )
    }
}

enum MotionPreferenceResolver {
    static func zoomAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.15)
    }

    static func standardAnimation(reduceMotion: Bool, duration: Double = 0.2) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}
