import XCTest

@MainActor
final class ImageBrowserUITests: XCTestCase {
    func testLaunchShowsOpenFolderButton() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app)
        launchAndWaitForMainWindow(app)

        XCTAssertTrue(app.buttons["Open Folder"].waitForExistence(timeout: 2.0))
    }

    func testLaunchWithFixtureFolderShowsImages() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        XCTAssertTrue(sidebarItem(named: "one-pixel.png", in: app).waitForExistence(timeout: 5.0))
        XCTAssertTrue(sidebarItem(named: "two-pixel.png", in: app).waitForExistence(timeout: 2.0))
        XCTAssertFalse(app.staticTexts["notes.txt"].exists)
        XCTAssertTrue(app.otherElements["current-image-info"].waitForExistence(timeout: 2.0))
    }

    func testFolderLoadFlowDisplaysImages() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app, folderURL: fixturesDirectory(named: "basic"))
        launchAndWaitForMainWindow(app)

        let firstSidebarItem = sidebarItem(named: "photo1.jpg", in: app)
        let lastSidebarItem = sidebarItem(named: "photo5.jpg", in: app)

        // Assert: All images appear in sidebar using the row accessibility label.
        XCTAssertTrue(firstSidebarItem.waitForExistence(timeout: 5.0), "First image should appear in sidebar")
        XCTAssertTrue(lastSidebarItem.waitForExistence(timeout: 2.0), "Last image should appear in sidebar")

        // Assert: Non-image file is filtered out
        XCTAssertFalse(app.staticTexts["readme.txt"].exists, "Text file should be filtered from image list")

        // Verify the sidebar summary reflects the five image fixtures.
        XCTAssertTrue(
            app.staticTexts["sidebar-status-label"].label.contains("5 images"),
            "Sidebar status should reflect the five loaded image fixtures"
        )
    }

    func testSmartCollectionSingleClickActivatesWithArrowAndStatus() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        XCTAssertTrue(app.staticTexts["one-pixel.png"].waitForExistence(timeout: 5.0))

        let favoriteButton = app.buttons.matching(identifier: "favorite-toggle").firstMatch
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 2.0), "Favorite button should be available")
        favoriteButton.click()

        let favoritesCollectionLabel = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'smart-collection-activate-' AND label == 'All Favorites'")
        ).firstMatch
        XCTAssertTrue(
            favoritesCollectionLabel.waitForExistence(timeout: 5.0),
            "Expected All Favorites preset collection to appear"
        )
        favoritesCollectionLabel.click()

        let activeIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'smart-collection-active-indicator-'")
        ).firstMatch
        XCTAssertTrue(
            activeIndicator.waitForExistence(timeout: 3.0),
            "The selected smart collection should show an active indicator"
        )

        let resetButtons = app.buttons.matching(identifier: "Show All Images")
        XCTAssertTrue(
            resetButtons.firstMatch.waitForExistence(timeout: 2.0),
            "Activating a smart collection should expose the reset action"
        )
    }

    func testFilterShortcutShowsAndHidesFiltersPanel() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        XCTAssertTrue(sidebarItem(named: "one-pixel.png", in: app).waitForExistence(timeout: 5.0))

        let filtersTitle = app.staticTexts["Filters"]

        app.activate()
        app.typeKey("f", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(filtersTitle.exists, "Cmd+F should remain available for Find semantics and must not toggle filters")

        app.activate()
        app.typeKey("f", modifierFlags: [.command, .shift])

        XCTAssertTrue(filtersTitle.waitForExistence(timeout: 2.0), "Filters panel should appear when using the command shortcut")

        app.activate()
        app.typeKey("f", modifierFlags: [.command, .shift])
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let hiddenPredicate = NSPredicate(format: "exists == false")
        expectation(for: hiddenPredicate, evaluatedWith: filtersTitle)
        waitForExpectations(timeout: 4.0)
    }

    func testFullscreenShortcutTogglesNativeFullscreenState() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app)
        launchAndWaitForMainWindow(app)

        let fullscreenState = app.descendants(matching: .any).matching(identifier: "fullscreen-state").firstMatch
        XCTAssertTrue(fullscreenState.waitForExistence(timeout: 2.0), "Fullscreen state probe should exist in UI test mode")

        XCTAssertTrue(
            waitForElementLabel(fullscreenState, equals: "windowed", timeout: 3.0),
            "App should start in windowed mode (\(describeElementState(fullscreenState)))"
        )

        app.activate()
        app.typeKey("f", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForElementLabel(fullscreenState, equals: "fullscreen", timeout: 4.0),
            "Cmd+Ctrl+F should enter native fullscreen (\(describeElementState(fullscreenState)))"
        )

        app.activate()
        app.typeKey("f", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForElementLabel(fullscreenState, equals: "windowed", timeout: 4.0),
            "Cmd+Ctrl+F should return to windowed mode when already fullscreen (\(describeElementState(fullscreenState)))"
        )
    }

    func testSidebarShortcutTogglesSidebarVisibility() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        let firstSidebarItem = sidebarItem(named: "one-pixel.png", in: app)
        XCTAssertTrue(firstSidebarItem.waitForExistence(timeout: 5.0), "Sidebar should start visible")
        XCTAssertTrue(
            waitForElementHittable(firstSidebarItem, isExpectedToBeHittable: true, timeout: 2.0),
            "A sidebar row should be interactable before toggling"
        )

        app.activate()
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForElementHittable(firstSidebarItem, isExpectedToBeHittable: false, timeout: 3.0),
            "Cmd+Ctrl+S should hide the sidebar"
        )

        app.activate()
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(
            waitForElementHittable(firstSidebarItem, isExpectedToBeHittable: true, timeout: 3.0),
            "Cmd+Ctrl+S should show the sidebar when hidden"
        )
    }

    func testShuffleShortcutTogglesShuffleMode() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        let shuffleButton = app.buttons.matching(identifier: "shuffle-toggle").firstMatch
        XCTAssertTrue(shuffleButton.waitForExistence(timeout: 2.0), "Shuffle control should be available")
        XCTAssertTrue(
            shuffleButton.label.contains("Disabled") || shuffleButton.label.contains("Off"),
            "Shuffle should start disabled"
        )

        app.activate()
        app.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForElementLabelContains(shuffleButton, substring: "Enabled", timeout: 2.0) ||
            waitForElementLabelContains(shuffleButton, substring: "On", timeout: 2.0),
            "Cmd+Shift+U should toggle shuffle on"
        )

        app.activate()
        app.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForElementLabelContains(shuffleButton, substring: "Disabled", timeout: 2.0) ||
            waitForElementLabelContains(shuffleButton, substring: "Off", timeout: 2.0),
            "Cmd+Shift+U should toggle shuffle off"
        )
    }

    func testArrowKeyDoesNotNavigateWhileEditingTextField() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        XCTAssertTrue(sidebarItem(named: "one-pixel.png", in: app).waitForExistence(timeout: 5.0))

        let currentImageInfo = app.otherElements["current-image-info"]
        XCTAssertTrue(currentImageInfo.waitForExistence(timeout: 2.0), "Current image overlay should be visible")

        app.typeKey("k", modifierFlags: [.command, .shift])
        let keywordWindow = app.windows["Keyword Manager"]
        XCTAssertTrue(keywordWindow.waitForExistence(timeout: 2.0), "Keyword Manager window should open")

        let tagInput = keywordWindow.textFields["New tag"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 2.0), "Keyword Manager should expose New tag field")
        tagInput.click()
        tagInput.typeText("test")

        let imageBeforeArrow = currentImageInfo.label
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForCurrentImageInfo(expected: imageBeforeArrow, in: app, timeout: 1.5),
            "Right arrow while editing a text field should not navigate images"
        )
    }

    func testKeywordManagerMenuCommandOpensWindow() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app)
        launchAndWaitForMainWindow(app)

        app.typeKey("k", modifierFlags: [.command, .shift])

        let tagsHeading = app.windows["Keyword Manager"].staticTexts["Tags"]
        XCTAssertTrue(tagsHeading.waitForExistence(timeout: 2.0), "Keyword Manager window should open from the Window menu")
    }

    private func makeFixtureDirectory() -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ImageBrowserUITests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let onePixelData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
        let twoPixelData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAADklEQVR4nGNg+A+FMAYAQ84H+fei4u8AAAAASUVORK5CYII=")
        let onePixelURL = tempDir.appendingPathComponent("one-pixel.png")
        let twoPixelURL = tempDir.appendingPathComponent("two-pixel.png")
        let notesURL = tempDir.appendingPathComponent("notes.txt")

        try? onePixelData?.write(to: onePixelURL)
        try? twoPixelData?.write(to: twoPixelURL)
        try? "not an image".data(using: .utf8)?.write(to: notesURL)

        return tempDir
    }

    private func makeTempDirectory() -> URL {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempURL = baseURL.appendingPathComponent("ImageBrowserUITests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL
    }

    private func fixturesDirectory(named name: String) -> URL {
        let testFileURL = URL(fileURLWithPath: #file, isDirectory: false)
        return testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/\(name)", isDirectory: true)
    }

    private func configureUITestEnvironment(for app: XCUIApplication, folderURL: URL? = nil) {
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        app.launchEnvironment["IMAGEBROWSER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["IMAGEBROWSER_RESET_DB"] = "1"

        let storageRoot = folderURL ?? makeTempDirectory()
        app.launchEnvironment["IMAGEBROWSER_TEST_DB_PATH"] = storageRoot
            .appendingPathComponent("ImageBrowserUITests.sqlite")
            .path

        if let folderURL {
            app.launchEnvironment["IMAGEBROWSER_TEST_FOLDER"] = folderURL.path
        }
    }

    private func launchAndWaitForMainWindow(_ app: XCUIApplication, timeout: TimeInterval = 5.0) {
        app.launch()
        app.activate()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: timeout),
            "Main window should exist before UI interactions"
        )
    }

    func testFailedImageRetryFlow() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app, folderURL: fixturesDirectory(named: "corrupted"))
        launchAndWaitForMainWindow(app)

        let validSidebarItem = sidebarItem(named: "valid.jpg", in: app)
        let truncatedSidebarItem = sidebarItem(named: "truncated.jpg", in: app)

        XCTAssertTrue(validSidebarItem.waitForExistence(timeout: 5.0), "Valid image should appear in sidebar")

        // Sort order is name-based, so select the valid image explicitly before asserting on the error state.
        validSidebarItem.click()
        XCTAssertFalse(app.staticTexts["error-display"].exists, "Valid image should clear any existing error state")

        // Click on first corrupted image
        XCTAssertTrue(truncatedSidebarItem.waitForExistence(timeout: 2.0), "Corrupted image should appear in sidebar")
        truncatedSidebarItem.click()

        // Assert: Error display appears
        XCTAssertTrue(app.staticTexts["error-display"].waitForExistence(timeout: 3.0), "Error message should appear for corrupted image")

        // Assert: Error indicator appears in sidebar for failed image
        let errorIndicators = app.descendants(matching: .any).matching(identifier: "error-indicator")
        XCTAssertTrue(errorIndicators.count > 0, "Error indicator should appear in sidebar for failed image")

        // Act: Navigate to valid image
        validSidebarItem.click()

        // Assert: Error display disappears
        XCTAssertFalse(app.staticTexts["error-display"].exists, "Error message should disappear when viewing valid image")

        // Act: Navigate back to corrupted image (implicit retry via selection change)
        truncatedSidebarItem.click()

        // Assert: Error still appears (retry fails again, image is still corrupted)
        XCTAssertTrue(app.staticTexts["error-display"].waitForExistence(timeout: 3.0), "Error message should still appear after retry")
    }

    func testSlideshowNavigationFlow() {
        let app = XCUIApplication()
        configureUITestEnvironment(for: app, folderURL: fixturesDirectory(named: "slideshow"))
        launchAndWaitForMainWindow(app)

        // Assert: Images loaded
        XCTAssertTrue(sidebarItem(named: "slide01.jpg", in: app).waitForExistence(timeout: 5.0), "First slide should appear in sidebar")
        XCTAssertTrue(sidebarItem(named: "slide10.jpg", in: app).waitForExistence(timeout: 2.0), "Last slide should appear in sidebar")

        // Assert: Initial current-image state is exposed
        let currentImageInfo = app.otherElements["current-image-info"]
        XCTAssertTrue(currentImageInfo.waitForExistence(timeout: 2.0), "Current image overlay should be visible")
        let initialImageLabel = currentImageInfo.label
        XCTAssertTrue(initialImageLabel.contains("slide"), "Current image overlay should describe the active slide")

        // Act: Start slideshow via button
        let slideshowButton = app.buttons.matching(identifier: "slideshow-toggle").firstMatch
        XCTAssertTrue(slideshowButton.waitForExistence(timeout: 2.0), "Slideshow button should exist")

        let initialToggleLabel = slideshowButton.label
        XCTAssertTrue(initialToggleLabel.contains("Start") || initialToggleLabel.contains("play"), "Button should show play state initially")

        slideshowButton.click()

        // Assert: Slideshow started (button shows "Stop" or "pause")
        let runningLabel = slideshowButton.label
        XCTAssertTrue(runningLabel.contains("Stop") || runningLabel.contains("pause"), "Button should show stop state after clicking")

        // Assert: slideshow advances the current image position
        let initialPositionValue = currentImageInfo.label
        XCTAssertTrue(
            waitForCurrentImageInfoChange(from: initialPositionValue, in: app, timeout: 6.0),
            "Slideshow should advance the current image"
        )

        let advancedImageLabel = currentImageInfo.label
        XCTAssertNotEqual(advancedImageLabel, initialImageLabel, "Slideshow should advance to a different slide")

        // Act: Stop slideshow
        slideshowButton.click()

        // Assert: Slideshow stopped (button shows "Start" or "play" again)
        let stoppedLabel = slideshowButton.label
        XCTAssertTrue(stoppedLabel.contains("Start") || stoppedLabel.contains("play"), "Button should show play state after stopping")

        // Act: Manually navigate to next image
        app.buttons["Next Image"].click()

        // Assert: Manual navigation worked (third image now selected)
        XCTAssertTrue(
            waitForCurrentImageInfoChange(from: advancedImageLabel, in: app, timeout: 2.0),
            "Manual navigation should advance to a different slide"
        )

        // Act: Start slideshow again
        slideshowButton.click()

        // Assert: Slideshow running again
        let runningLabel2 = slideshowButton.label
        XCTAssertTrue(runningLabel2.contains("Stop") || runningLabel2.contains("pause"), "Button should show stop state after restarting")

        // Act: Stop slideshow (cleanup)
        slideshowButton.click()

        // Assert: Slideshow stopped
        let finalLabel = slideshowButton.label
        XCTAssertTrue(finalLabel.contains("Start") || finalLabel.contains("play"), "Button should show play state at end")
    }

    func testKeyboardArrowNavigationChangesCurrentImage() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        let currentImageInfo = app.otherElements["current-image-info"]
        XCTAssertTrue(currentImageInfo.waitForExistence(timeout: 5.0), "Current image overlay should be visible")
        let initialLabel = currentImageInfo.label

        app.activate()
        currentImageInfo.click()

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForCurrentImageInfoChange(from: initialLabel, in: app, timeout: 2.0),
            "Right arrow should change current image"
        )

        let rightLabel = currentImageInfoLabel(in: app)
        app.activate()
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForCurrentImageInfo(expected: initialLabel, in: app, timeout: 2.0),
            "Left arrow should return to the original image"
        )
        XCTAssertNotEqual(rightLabel, initialLabel, "Right arrow should change current image")
    }

    func testRightArrowNavigatesWhenSidebarSelectionHasFocus() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        let firstRow = sidebarItem(named: "one-pixel.png", in: app)
        let secondRow = sidebarItem(named: "two-pixel.png", in: app)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5.0), "First sidebar row should exist")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 2.0), "Second sidebar row should exist")

        let currentImageInfo = app.otherElements["current-image-info"]
        XCTAssertTrue(currentImageInfo.waitForExistence(timeout: 2.0), "Current image overlay should be visible")
        let initialLabel = currentImageInfo.label

        firstRow.click()
        app.activate()
        app.typeKey(.rightArrow, modifierFlags: [])

        XCTAssertTrue(
            waitForCurrentImageInfoChange(from: initialLabel, in: app, timeout: 2.0),
            "Right arrow should navigate even when sidebar table focus is active"
        )
    }

    func testSmartCollectionsNewButtonIsExposedForAccessibility() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        let newCollectionButton = app.buttons["smart-collections-new-button"]
        XCTAssertTrue(
            newCollectionButton.waitForExistence(timeout: 3.0),
            "Smart Collections add button should be discoverable by accessibility identifier"
        )

        XCTAssertEqual(
            newCollectionButton.label,
            "New Smart Collection",
            "Smart Collections add button should expose a descriptive accessibility label"
        )
    }

    func testMemoryStabilityUnderStress() async {
        let imageCount = 60
        let forwardNavigationCount = 40
        let reverseNavigationCount = 15
        let jumpTargets = stride(from: 0, to: imageCount, by: 10).map { $0 }

        // Arrange: Create test folder with enough images to churn caches without making XCTest unusably slow.
        let tempDir = makeTempDirectory()

        // Create small images programmatically.
        // Memory stress comes from cache churn, not image size
        let onePixelData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
        let twoPixelData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAADklEQVR4nGNg+A+FMAYAQ84H+fei4u8AAAAASUVORK5CYII=")

        for i in 1...imageCount {
            let filename = String(format: "img%03d.jpg", i)
            let destURL = tempDir.appendingPathComponent(filename)

            // Use minimal JPEG data (1KB) for rapid navigation testing
            if i % 2 == 0 {
                try? onePixelData?.write(to: destURL)
            } else {
                try? twoPixelData?.write(to: destURL)
            }
        }

        let app = XCUIApplication()
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        // Assert: Images loaded (progressive loading handles large folders)
        XCTAssertTrue(
            sidebarItem(named: "img001.jpg", in: app).waitForExistence(timeout: 10.0),
            "First image should load (progressive loading may take time)"
        )
        XCTAssertTrue(
            sidebarItem(named: String(format: "img%03d.jpg", imageCount), in: app).waitForExistence(timeout: 5.0),
            "Last image should eventually load"
        )
        let currentImageInfo = app.otherElements["current-image-info"]
        XCTAssertTrue(currentImageInfo.waitForExistence(timeout: 2.0), "Current image state should be exposed")
        let initialImageLabel = currentImageInfoLabel(in: app)

        // Stress: Rapid navigation through a substantial slice of the folder.
        // This tests cache eviction, prefetch cancellation, and task cleanup
        for _ in 0..<forwardNavigationCount {
            // Navigate to next image via keyboard shortcut
            app.typeKey(.rightArrow, modifierFlags: [])

            // Suspend without blocking the main actor run loop.
            try? await Task.sleep(for: .milliseconds(30))
        }

        // Navigate back to start (tests cache eviction in reverse)
        for _ in 0..<reverseNavigationCount {
            app.typeKey(.leftArrow, modifierFlags: [])
            try? await Task.sleep(for: .milliseconds(30))
        }

        // Jump to random images (tests prefetch cancellation on distant jumps)
        for index in jumpTargets {
            // Click sidebar item directly to test rapid switching
            sidebarItem(named: String(format: "img%03d.jpg", index + 1), in: app).click()
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Assert: App still responsive after stress
        XCTAssertTrue(currentImageInfo.exists, "App should still be responsive after stress")
        let stressedImageLabel = currentImageInfoLabel(in: app)
        XCTAssertFalse(stressedImageLabel.isEmpty, "Stress navigation should keep a current image selected")
        XCTAssertNotEqual(stressedImageLabel, initialImageLabel, "Stress navigation should change the selected image")

        // Assert: Can still navigate normally
        let labelBeforeFinalNavigation = currentImageInfoLabel(in: app)
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForCurrentImageInfoChange(from: labelBeforeFinalNavigation, in: app, timeout: 2.0),
            "Should navigate to the next image after stress"
        )
    }

    private func sidebarItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar-item-'"))
    }

    private func sidebarItem(named name: String, in app: XCUIApplication) -> XCUIElement {
        sidebarItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    private func currentImageInfoLabel(in app: XCUIApplication) -> String {
        app.otherElements["current-image-info"].label
    }

    private func waitForCurrentImageInfoChange(from originalLabel: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let currentLabel = currentImageInfoLabel(in: app)
            if !currentLabel.isEmpty && currentLabel != originalLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForCurrentImageInfo(expected expectedLabel: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentImageInfoLabel(in: app) == expectedLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForElementLabel(_ element: XCUIElement, equals expectedLabel: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (element.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if element.exists && (label == expectedLabel || value == expectedLabel) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForElementHittable(_ element: XCUIElement, isExpectedToBeHittable: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isExpectedToBeHittable {
                if element.exists && element.isHittable {
                    return true
                }
            } else if !element.exists || !element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForElementLabelContains(_ element: XCUIElement, substring: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label.contains(substring) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func describeElementState(_ element: XCUIElement) -> String {
        let valueDescription = (element.value as? String) ?? "<nil>"
        return "exists=\(element.exists), label='\(element.label)', value='\(valueDescription)'"
    }

}
