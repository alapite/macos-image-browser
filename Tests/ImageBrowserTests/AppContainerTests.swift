import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class AppContainerTests: XCTestCase {
    func testAppDatabase_usesExplicitOverridePath() throws {
        let directory = makeTempDirectory()
        let databaseURL = directory.appendingPathComponent("explicit.sqlite")

        _ = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: databaseURL.path,
                resetOnLaunch: false
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testAppContainer_uiTestModeUsesVolatilePreferencesStore() throws {
        UserDefaults.standard.removeObject(forKey: "ImageBrowserPreferences")

        let directory = makeTempDirectory()
        let database = AppDatabase(
            configuration: AppDatabaseConfiguration(
                overridePath: directory.appendingPathComponent("container.sqlite").path,
                resetOnLaunch: false
            )
        )

        let container = AppContainer(
            database: database,
            processInfo: TestEnvironmentProvider(environment: ["IMAGEBROWSER_UI_TEST_MODE": "1"])
        )

        container.appState.updateSlideshowInterval(4.5)

        XCTAssertNil(
            UserDefaults.standard.data(forKey: "ImageBrowserPreferences"),
            "UI test mode should avoid writing through UserDefaults"
        )
    }
}
