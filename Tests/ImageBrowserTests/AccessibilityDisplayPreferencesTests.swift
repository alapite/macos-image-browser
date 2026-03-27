import XCTest
@testable import ImageBrowser

final class AccessibilityDisplayPreferencesTests: XCTestCase {
    func testViewerBackgroundStyle_usesSolidBackgroundWhenReduceTransparencyEnabled() {
        let style = ViewerBackgroundVisualStyleResolver.resolve(
            reduceTransparency: true,
            colorContrast: .standard
        )

        XCTAssertTrue(style.usesSolidBackground)
        XCTAssertEqual(style.radialHighlightOpacity, 0.0)
    }

    func testViewerBackgroundStyle_reducesHighlightForIncreasedContrast() {
        let standard = ViewerBackgroundVisualStyleResolver.resolve(
            reduceTransparency: false,
            colorContrast: .standard
        )
        let increased = ViewerBackgroundVisualStyleResolver.resolve(
            reduceTransparency: false,
            colorContrast: .increased
        )

        XCTAssertFalse(standard.usesSolidBackground)
        XCTAssertFalse(increased.usesSolidBackground)
        XCTAssertLessThan(increased.radialHighlightOpacity, standard.radialHighlightOpacity)
    }

    func testMotionPreferenceResolver_disablesAnimationsWhenReduceMotionEnabled() {
        XCTAssertNil(MotionPreferenceResolver.zoomAnimation(reduceMotion: true))
        XCTAssertNil(MotionPreferenceResolver.standardAnimation(reduceMotion: true))
    }

    func testMotionPreferenceResolver_providesAnimationsWhenReduceMotionDisabled() {
        XCTAssertNotNil(MotionPreferenceResolver.zoomAnimation(reduceMotion: false))
        XCTAssertNotNil(MotionPreferenceResolver.standardAnimation(reduceMotion: false))
    }
}
