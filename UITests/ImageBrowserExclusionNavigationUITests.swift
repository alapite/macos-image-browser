import XCTest

@MainActor
final class ImageBrowserExclusionNavigationUITests: XCTestCase {

    func testArrowKeyNavigationSkipsExcludedImages() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectoryWithNamedImages(count: 5)
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        // Wait for sidebar content to load
        guard waitForSidebarToLoad(in: app, timeout: 15.0) else {
            XCTFail("Sidebar should load images")
            return
        }
        guard waitForSidebarItem(named: "image4.png", in: app, timeout: 5.0) != nil else {
            XCTFail("Fifth image should appear")
            return
        }

        let currentImageInfo = app.otherElements["current-image-info"]
        guard currentImageInfo.waitForExistence(timeout: 2.0) else {
            XCTFail("Current image info should be visible")
            return
        }

        // Navigate to second image (index 1)
        app.activate()
        currentImageInfo.click()
        app.typeKey(.rightArrow, modifierFlags: [])

        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Should be on second image")
            return
        }
        let secondImageLabel = currentImageInfo.label

        // Exclude the third image (index 2) by navigating to it and using context menu
        app.typeKey(.rightArrow, modifierFlags: [])
        guard waitForCurrentImageInfoChange(from: secondImageLabel, in: app, timeout: 2.0) else {
            XCTFail("Should move to third image before exclusion")
            return
        }
        // Right-click the current image row in the sidebar to open row context menu
        guard let thirdSidebarItem = hittableSidebarItem(named: "image2.png", in: app) else {
            XCTFail("Third sidebar item should exist")
            return
        }
        thirdSidebarItem.rightClick()

        // Wait for context menu and click "Exclude from Browsing"
        let excludeMenuItem = app.menuItems["Exclude from Browsing"]
        guard excludeMenuItem.waitForExistence(timeout: 2.0) else {
            XCTFail("Exclude menu item should exist")
            return
        }
        excludeMenuItem.click()
        guard waitForSidebarItemToBeExcluded(named: "image2.png", in: app, timeout: 3.0) else {
            XCTFail("Exclusion should persist before navigation assertions")
            return
        }

        // Now navigate back to second image
        app.typeKey(.leftArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Should be back on second image")
            return
        }
        let backToSecondLabel = currentImageInfo.label

        guard backToSecondLabel.contains("image1.png") else {
            XCTFail("Precondition failed: expected to be on second image before skip check")
            return
        }

        // Right-arrow should skip the excluded third image and go to fourth.
        app.typeKey(.rightArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image3.png", in: app, timeout: 2.0) else {
            XCTFail("Right arrow should skip excluded third image and go to fourth")
            return
        }

        // Left-arrow from fourth should skip excluded third and return to second.
        app.typeKey(.leftArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Left arrow should skip excluded third image and return to second")
            return
        }
    }

    func testUpAndDownArrowNavigationSkipsExcludedImages() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectoryWithNamedImages(count: 5)
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        guard waitForSidebarToLoad(in: app, timeout: 15.0) else {
            XCTFail("Sidebar should load images")
            return
        }

        let currentImageInfo = app.otherElements["current-image-info"]
        guard currentImageInfo.waitForExistence(timeout: 2.0) else {
            XCTFail("Current image info should be visible")
            return
        }

        app.activate()
        currentImageInfo.click()

        // Move to second image.
        app.typeKey(.downArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Should be on second image")
            return
        }

        // Move to third and exclude it.
        app.typeKey(.downArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image2.png", in: app, timeout: 2.0) else {
            XCTFail("Should be on third image before exclusion")
            return
        }
        guard let thirdSidebarItem = hittableSidebarItem(named: "image2.png", in: app) else {
            XCTFail("Third sidebar item should exist")
            return
        }
        thirdSidebarItem.rightClick()
        let excludeMenuItem = app.menuItems["Exclude from Browsing"]
        guard excludeMenuItem.waitForExistence(timeout: 2.0) else {
            XCTFail("Exclude menu item should exist")
            return
        }
        excludeMenuItem.click()
        guard waitForSidebarItemToBeExcluded(named: "image2.png", in: app, timeout: 3.0) else {
            XCTFail("Exclusion should persist before up/down assertions")
            return
        }

        // Return to second image.
        app.typeKey(.upArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Should be back on second image")
            return
        }

        // Down-arrow should skip excluded third and go to fourth.
        app.typeKey(.downArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image3.png", in: app, timeout: 2.0) else {
            XCTFail("Down arrow should skip excluded third image and go to fourth")
            return
        }

        // Up-arrow should skip excluded third and return to second.
        app.typeKey(.upArrow, modifierFlags: [])
        guard waitForCurrentImageInfoToContain("image1.png", in: app, timeout: 2.0) else {
            XCTFail("Up arrow should skip excluded third image and return to second")
            return
        }
    }

    func testDirectClickOnExcludedImageSkipsToNearestEligibleImage() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectoryWithNamedImages(count: 3)
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        // Wait for images to load
        guard waitForSidebarToLoad(in: app, timeout: 15.0) else {
            XCTFail("Sidebar should load images")
            return
        }

        let currentImageInfo = app.otherElements["current-image-info"]
        guard currentImageInfo.waitForExistence(timeout: 2.0) else {
            XCTFail("Current image info should be visible")
            return
        }

        // Exclude the second image
        guard let secondSidebarItem = hittableSidebarItem(named: "image1.png", in: app) else {
            XCTFail("Second sidebar item should exist")
            return
        }

        secondSidebarItem.rightClick()
        let excludeMenuItem = app.menuItems["Exclude from Browsing"]
        guard excludeMenuItem.waitForExistence(timeout: 2.0) else {
            XCTFail("Exclude menu item should exist")
            return
        }
        excludeMenuItem.click()
        guard waitForSidebarItemToBeExcluded(named: "image1.png", in: app, timeout: 3.0) else {
            XCTFail("Exclusion should persist before click-navigation assertions")
            return
        }

        // Click directly on the excluded thumbnail - app should skip excluded items
        secondSidebarItem.click()
        guard waitForCurrentImageInfoToContain("image2.png", in: app, timeout: 2.0) else {
            XCTFail("Excluded image selection should advance to the nearest eligible image")
            return
        }
        let currentImageLabel = currentImageInfo.label

        XCTAssertFalse(currentImageLabel.contains("image1.png"), "Should not remain on excluded image")
        XCTAssertTrue(currentImageLabel.contains("image2.png"), "Should advance to the next eligible image")
    }

    func testExcludingAllImagesMarksRowsExcluded() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectoryWithNamedImages(count: 3)
        configureUITestEnvironment(for: app, folderURL: tempDir)
        launchAndWaitForMainWindow(app)

        // Wait for images to load
        guard waitForSidebarToLoad(in: app, timeout: 15.0) else {
            XCTFail("Sidebar should load images")
            return
        }

        let currentImageInfo = app.otherElements["current-image-info"]
        guard currentImageInfo.waitForExistence(timeout: 2.0) else {
            XCTFail("Current image info should be visible")
            return
        }

        // Exclude all three images by name for deterministic targeting.
        for imageName in ["image0.png", "image1.png", "image2.png"] {
            guard let sidebarItem = waitForSidebarItem(named: imageName, in: app, timeout: 5.0) else {
                XCTFail("Expected sidebar item \(imageName) to exist")
                return
            }

            sidebarItem.rightClick()
            let excludeMenuItem = app.menuItems["Exclude from Browsing"]
            guard excludeMenuItem.waitForExistence(timeout: 2.0) else {
                XCTFail("Exclude menu item should exist")
                return
            }
            excludeMenuItem.click()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }

        XCTAssertTrue(currentImageInfo.exists, "Current image info should remain available after exclusions")
    }

    // MARK: - Helper Functions

    private func sidebarItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar-item-'"))
    }

    private func sidebarItem(named name: String, in app: XCUIApplication) -> XCUIElement {
        sidebarItems(in: app).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    private func waitForSidebarToLoad(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if firstHittableSidebarRow(in: app) != nil {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForSidebarItem(named name: String, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = hittableSidebarItem(named: name, in: app) {
                return row
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    private func hittableSidebarItem(named name: String, in app: XCUIApplication) -> XCUIElement? {
        let candidates = sidebarItems(in: app)
            .matching(NSPredicate(format: "label CONTAINS %@", name))
            .allElementsBoundByIndex
        return candidates.first(where: isSidebarRow) ?? candidates.first(where: { $0.exists })
    }

    private func firstHittableSidebarRow(in app: XCUIApplication) -> XCUIElement? {
        sidebarItems(in: app).allElementsBoundByIndex.first(where: isSidebarRow)
    }

    private func isSidebarRow(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && element.frame.width > 40 && element.frame.height > 12
    }

    private func waitForCurrentImageInfoChange(from originalLabel: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let currentImageInfo = app.otherElements["current-image-info"]
        let predicate = NSPredicate(format: "label != %@", originalLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: currentImageInfo)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForCurrentImageInfoToContain(_ text: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let currentImageInfo = app.otherElements["current-image-info"]
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: currentImageInfo)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForSidebarItemToBeExcluded(named name: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'excluded from browsing'", name)
        let excludedRow = sidebarItems(in: app).matching(predicate).firstMatch

        while Date() < deadline {
            if excludedRow.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return false
    }

    private func makeFixtureDirectoryWithNamedImages(count: Int) -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")

        for i in 0..<count {
            let imageURL = tempDir.appendingPathComponent("image\(i).png")
            try? onePixelPNG?.write(to: imageURL)
        }

        return tempDir
    }

    private func makeTempDirectory() -> URL {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempURL = baseURL.appendingPathComponent("ImageBrowserUITests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL
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
}
