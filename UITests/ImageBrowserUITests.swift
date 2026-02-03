import XCTest

final class ImageBrowserUITests: XCTestCase {
    func testLaunchShowsOpenFolderButton() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Open Folder"].waitForExistence(timeout: 2.0))
    }

    func testLaunchWithFixtureFolderShowsImages() {
        let app = XCUIApplication()
        let tempDir = makeFixtureDirectory()
        app.launchEnvironment["IMAGEBROWSER_TEST_FOLDER"] = tempDir.path
        app.launch()

        XCTAssertTrue(app.staticTexts["one-pixel.png"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["two-pixel.png"].waitForExistence(timeout: 2.0))
        XCTAssertFalse(app.staticTexts["notes.txt"].exists)
        XCTAssertTrue(app.images["main-image"].waitForExistence(timeout: 2.0))
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
}
