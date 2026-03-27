import XCTest
@testable import ImageBrowser

@MainActor
final class ViewStoreZoomTests: XCTestCase {

    var viewStore: ViewStore!

    override func setUp() async throws {
        viewStore = ViewStore()
    }

    override func tearDown() async throws {
        viewStore = nil
    }

    // MARK: - Zoom Preset Tests

    func test_setZoomPreset_25_setsZoomTo0_25() {
        // When
        viewStore.setZoomPreset(25)

        // Then
        XCTAssertEqual(viewStore.currentZoom, 0.25, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_setZoomPreset_50_setsZoomTo0_5() {
        // When
        viewStore.setZoomPreset(50)

        // Then
        XCTAssertEqual(viewStore.currentZoom, 0.5, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_setZoomPreset_100_setsZoomTo1_0_andModeToActual() {
        // When
        viewStore.setZoomPreset(100)

        // Then
        XCTAssertEqual(viewStore.currentZoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .actual)
    }

    func test_setZoomPreset_200_setsZoomTo2_0() {
        // When
        viewStore.setZoomPreset(200)

        // Then
        XCTAssertEqual(viewStore.currentZoom, 2.0, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_setZoomPreset_400_setsZoomTo4_0() {
        // When
        viewStore.setZoomPreset(400)

        // Then
        XCTAssertEqual(viewStore.currentZoom, 4.0, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    // MARK: - Actual Size Tests

    func test_actualSize_setsZoomTo1_0_andModeToActual() {
        // Given
        viewStore.currentZoom = 2.5
        viewStore.zoomMode = .custom

        // When
        viewStore.actualSize()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .actual)
    }

    // MARK: - Fit To Both Tests

    func test_fitToBoth_setsZoomModeToFit() {
        // Given
        viewStore.currentZoom = 2.5
        viewStore.zoomMode = .custom

        // When
        viewStore.fitToBoth()

        // Then
        XCTAssertEqual(viewStore.zoomMode, .fit)
        XCTAssertEqual(viewStore.currentZoom, 1.0, accuracy: 0.01, "currentZoom should reset to 1.0 fit baseline")
    }

    func test_fitToBoth_resetsCurrentZoomToFitBaseline() {
        // Given: ViewStore with custom zoom
        viewStore.currentZoom = 2.5
        viewStore.zoomMode = .custom

        // When: Fit to both is triggered
        viewStore.fitToBoth()

        // Then: Fit mode uses the standard fit baseline zoom
        XCTAssertEqual(viewStore.zoomMode, .fit, "zoomMode should be .fit")
        XCTAssertEqual(viewStore.currentZoom, 1.0, accuracy: 0.01, "currentZoom should reset to 1.0 fit baseline")
    }

    func test_fitToBoth_setsNeedsRefitTrigger() {
        // Given: ViewStore in custom zoom mode
        viewStore.currentZoom = 2.5
        viewStore.zoomMode = .custom
        viewStore.needsRefit = false

        // When: Fit to both is triggered
        viewStore.fitToBoth()

        // Then: needsRefit should be true to signal the view layer to recalculate
        XCTAssertTrue(viewStore.needsRefit, "needsRefit should be true after fitToBoth() is called")
    }

    func test_needsRefit_initiallyFalse() {
        // Then: needsRefit should start as false
        XCTAssertFalse(viewStore.needsRefit, "needsRefit should be false initially")
    }

    func test_zoomMode_initiallyFit() {
        // Then: Images should start in fit mode by default
        XCTAssertEqual(viewStore.zoomMode, .fit, "zoomMode should be .fit on initialization")
    }

    func test_needsRefit_canBeTriggeredMultipleTimes() {
        // Given: ViewStore in fit mode
        viewStore.zoomMode = .fit
        viewStore.needsRefit = false

        // When: Trigger refit multiple times
        viewStore.fitToBoth()
        let firstTrigger = viewStore.needsRefit

        viewStore.needsRefit = false
        viewStore.fitToBoth()
        let secondTrigger = viewStore.needsRefit

        // Then: Each trigger should work independently
        XCTAssertTrue(firstTrigger, "First trigger should set needsRefit to true")
        XCTAssertTrue(secondTrigger, "Second trigger should also set needsRefit to true")
    }

    // MARK: - Zoom In Tests

    func test_zoomIn_from1_0_increasesBy25Percent() {
        // Given
        viewStore.currentZoom = 1.0

        // When
        viewStore.zoomIn()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomIn_from2_0_increasesBy25Percent() {
        // Given
        viewStore.currentZoom = 2.0

        // When
        viewStore.zoomIn()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 2.5, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomIn_capsAt5_0() {
        // Given
        viewStore.currentZoom = 4.5

        // When
        viewStore.zoomIn()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 5.0, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomIn_at5_0_staysAt5_0() {
        // Given
        viewStore.currentZoom = 5.0

        // When
        viewStore.zoomIn()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 5.0, accuracy: 0.001)
    }

    // MARK: - Zoom Out Tests

    func test_zoomOut_from1_0_decreasesBy20Percent() {
        // Given
        viewStore.currentZoom = 1.0

        // When
        viewStore.zoomOut()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 0.8, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomOut_from2_0_decreasesBy20Percent() {
        // Given
        viewStore.currentZoom = 2.0

        // When
        viewStore.zoomOut()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 1.6, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomOut_capsAt0_1() {
        // Given
        viewStore.currentZoom = 0.15

        // When
        viewStore.zoomOut()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 0.1, accuracy: 0.001)
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomOut_at0_1_staysAt0_1() {
        // Given
        viewStore.currentZoom = 0.1

        // When
        viewStore.zoomOut()

        // Then
        XCTAssertEqual(viewStore.currentZoom, 0.1, accuracy: 0.001)
    }

    // MARK: - Zoom Mode Tracking Tests

    func test_zoomMode_tracksCustom_afterZoomIn() {
        // Given
        viewStore.zoomMode = .actual
        viewStore.currentZoom = 1.0

        // When
        viewStore.zoomIn()

        // Then
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomMode_tracksCustom_afterZoomOut() {
        // Given
        viewStore.zoomMode = .actual
        viewStore.currentZoom = 1.0

        // When
        viewStore.zoomOut()

        // Then
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomMode_tracksCustom_afterNon100Preset() {
        // Given
        viewStore.zoomMode = .actual

        // When
        viewStore.setZoomPreset(50)

        // Then
        XCTAssertEqual(viewStore.zoomMode, .custom)
    }

    func test_zoomMode_tracksActual_after100Preset() {
        // Given
        viewStore.zoomMode = .custom

        // When
        viewStore.setZoomPreset(100)

        // Then
        XCTAssertEqual(viewStore.zoomMode, .actual)
    }

    // MARK: - Viewer Effective Scale Tests

    func test_mainImageZoomScale_fitMode_ignoresCurrentZoom() {
        // Given
        let zoomMode = ViewStore.ZoomMode.fit
        let currentZoom = 2.5

        // When
        let effectiveScale = MainImageZoomScaleResolver.effectiveScale(
            zoomMode: zoomMode,
            currentZoom: currentZoom
        )

        // Then
        XCTAssertEqual(effectiveScale, 1.0, accuracy: 0.001)
    }

    func test_mainImageZoomScale_customMode_usesCurrentZoom() {
        // Given
        let zoomMode = ViewStore.ZoomMode.custom
        let currentZoom = 1.8

        // When
        let effectiveScale = MainImageZoomScaleResolver.effectiveScale(
            zoomMode: zoomMode,
            currentZoom: currentZoom
        )

        // Then
        XCTAssertEqual(effectiveScale, 1.8, accuracy: 0.001)
    }
}
