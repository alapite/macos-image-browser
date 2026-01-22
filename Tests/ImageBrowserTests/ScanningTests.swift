import XCTest
@testable import ImageBrowser

final class ScanningTests: XCTestCase {
    func testLoadImagesFiltersBySupportedExtensionsCaseInsensitive() {
        let folder = URL(fileURLWithPath: "/tmp/ImageBrowserTests/fixtures")

        let urls = [
            folder.appendingPathComponent("a.JPG"),
            folder.appendingPathComponent("b.jpeg"),
            folder.appendingPathComponent("c.png"),
            folder.appendingPathComponent("d.txt"),
            folder.appendingPathComponent("e"),
        ]

        let fileSystem = FakeFileSystem(
            files: urls,
            creationDates: [
                urls[0]: makeDate(year: 2020, month: 1, day: 1),
                urls[1]: makeDate(year: 2020, month: 1, day: 2),
                urls[2]: makeDate(year: 2020, month: 1, day: 3),
                urls[3]: makeDate(year: 2020, month: 1, day: 4),
                urls[4]: makeDate(year: 2020, month: 1, day: 5),
            ]
        )

        let state = AppState(
            preferencesStore: InMemoryPreferencesStore(),
            fileSystem: fileSystem
        )

        state.loadImages(from: folder)

        XCTAssertEqual(state.images.map(\.name).sorted(), ["a.JPG", "b.jpeg", "c.png"].sorted())
        XCTAssertTrue(state.failedImages.isEmpty)
    }

    func testLoadImagesTracksFailedImagesWhenMetadataReadFails() {
        let folder = URL(fileURLWithPath: "/tmp/ImageBrowserTests/fixtures")

        let ok = folder.appendingPathComponent("ok.jpg")
        let bad = folder.appendingPathComponent("bad.jpg")

        let fileSystem = FakeFileSystem(
            files: [ok, bad],
            creationDates: [
                ok: makeDate(year: 2020, month: 1, day: 1),
            ],
            failingCreationDates: Set([bad])
        )

        let state = AppState(
            preferencesStore: InMemoryPreferencesStore(),
            fileSystem: fileSystem
        )

        state.loadImages(from: folder)

        XCTAssertEqual(state.images.map(\.name), ["ok.jpg"])
        XCTAssertEqual(state.failedImages, Set([bad]))
    }
}

private final class InMemoryPreferencesStore: PreferencesStore {
    private var stored: Preferences? = nil

    func load() -> Preferences? {
        stored
    }

    func save(_ preferences: Preferences) {
        stored = preferences
    }
}

private struct FakeFileSystem: FileSystem {
    let files: [URL]
    let creationDates: [URL: Date]
    let failingCreationDates: Set<URL>

    init(
        files: [URL],
        creationDates: [URL: Date],
        failingCreationDates: Set<URL> = []
    ) {
        self.files = files
        self.creationDates = creationDates
        self.failingCreationDates = failingCreationDates
    }

    func enumerateFiles(
        in folder: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> AnySequence<URL> {
        AnySequence(files)
    }

    func creationDate(for fileURL: URL) throws -> Date {
        if failingCreationDates.contains(fileURL) {
            throw CocoaError(.fileReadNoPermission)
        }
        guard let date = creationDates[fileURL] else {
            throw CocoaError(.fileReadUnknown)
        }
        return date
    }

    func fileExists(atPath path: String) -> Bool {
        true
    }
}
