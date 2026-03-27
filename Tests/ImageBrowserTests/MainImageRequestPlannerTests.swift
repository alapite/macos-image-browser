import XCTest
@testable import ImageBrowser

final class MainImageRequestPlannerTests: XCTestCase {
    func test_targetPixelSize_fitMode_usesQualityMultiplier() {
        let base = MainImageRequestPlanner.basePixelSize(
            viewportMaxPixelSize: 1200,
            normalize: { $0 }
        )

        let target = MainImageRequestPlanner.targetPixelSize(
            viewportMaxPixelSize: 1200,
            zoomMode: .fit,
            currentZoom: 2.5,
            normalize: { $0 }
        )

        XCTAssertEqual(base, 1200)
        XCTAssertEqual(target, 1800)
    }

    func test_targetPixelSize_fitMode_ignoresCurrentZoomValue() {
        let lowZoom = MainImageRequestPlanner.targetPixelSize(
            viewportMaxPixelSize: 1200,
            zoomMode: .fit,
            currentZoom: 1.0,
            normalize: { $0 }
        )
        let highZoom = MainImageRequestPlanner.targetPixelSize(
            viewportMaxPixelSize: 1200,
            zoomMode: .fit,
            currentZoom: 4.0,
            normalize: { $0 }
        )

        XCTAssertEqual(lowZoom, highZoom)
        XCTAssertEqual(highZoom, 1800)
    }

    func test_targetPixelSize_customMode_scalesByZoomFactorWhenAbove100Percent() {
        let target = MainImageRequestPlanner.targetPixelSize(
            viewportMaxPixelSize: 1200,
            zoomMode: .custom,
            currentZoom: 1.8,
            normalize: { $0 }
        )

        XCTAssertEqual(target, 2160)
    }

    func test_targetPixelSize_customMode_clampsZoomBelow100PercentToBase() {
        let target = MainImageRequestPlanner.targetPixelSize(
            viewportMaxPixelSize: 1200,
            zoomMode: .custom,
            currentZoom: 0.6,
            normalize: { $0 }
        )

        XCTAssertEqual(target, 1200)
    }

    func test_shouldUpgradeImage_returnsTrueOnlyWhenTargetExceedsLoadedSize() {
        let shouldUpgradeFromBase = MainImageRequestPlanner.shouldUpgradeImage(
            loadedPixelSize: nil,
            basePixelSize: 1200,
            targetPixelSize: 2400
        )
        let shouldNotUpgradeAtParity = MainImageRequestPlanner.shouldUpgradeImage(
            loadedPixelSize: 2400,
            basePixelSize: 1200,
            targetPixelSize: 2400
        )

        XCTAssertTrue(shouldUpgradeFromBase)
        XCTAssertFalse(shouldNotUpgradeAtParity)
    }

    func test_upgradeDebounce_fitMode_isImmediate() {
        let fitDebounce = MainImageRequestPlanner.upgradeDebounceNanoseconds(zoomMode: .fit)
        let customDebounce = MainImageRequestPlanner.upgradeDebounceNanoseconds(zoomMode: .custom)

        XCTAssertEqual(fitDebounce, 0)
        XCTAssertEqual(customDebounce, 150_000_000)
    }
}
