import XCTest
@testable import ImageBrowser

final class PreferencesTests: XCTestCase {
    func testPreferencesEncodesAndDecodesRoundTrip() throws {
        let original = Preferences(
            slideshowInterval: 4.5,
            sortOrder: AppState.SortOrder.custom.rawValue,
            customOrder: ["b.jpg", "a.jpg"],
            lastFolder: "/tmp/some-folder"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertEqual(decoded.slideshowInterval, original.slideshowInterval)
        XCTAssertEqual(decoded.sortOrder, original.sortOrder)
        XCTAssertEqual(decoded.customOrder, original.customOrder)
        XCTAssertEqual(decoded.lastFolder, original.lastFolder)
    }

    func testPreferencesDecodingIsSafeWhenLastFolderMissing() throws {
        let json = """
        {
          "slideshowInterval": 3,
          "sortOrder": "Name",
          "customOrder": []
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertNil(decoded.lastFolder)
        XCTAssertEqual(decoded.slideshowInterval, 3)
        XCTAssertEqual(decoded.sortOrder, "Name")
        XCTAssertEqual(decoded.customOrder, [])
    }

    func testUserDefaultsPreferencesStoreRoundTripDoesNotTouchStandardDefaults() {
        let userDefaults = makeIsolatedUserDefaults()
        let store = UserDefaultsPreferencesStore(userDefaults: userDefaults)

        XCTAssertNil(store.load())

        let prefs = Preferences(
            slideshowInterval: 2.0,
            sortOrder: AppState.SortOrder.name.rawValue,
            customOrder: [],
            lastFolder: nil
        )

        store.save(prefs)

        XCTAssertEqual(store.load()?.slideshowInterval, 2.0)
        XCTAssertEqual(store.load()?.sortOrder, AppState.SortOrder.name.rawValue)
    }
}
