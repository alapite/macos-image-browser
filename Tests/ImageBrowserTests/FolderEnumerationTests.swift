import XCTest
@testable import ImageBrowser

@MainActor
final class FolderEnumerationTests: XCTestCase {
    func testLoadImages_enumeratesSupportedImagesSkippingHiddenAndNonImages() async {
        let preferencesStore = InMemoryPreferencesStore()
        let sut = makeAppState(preferencesStore: preferencesStore)
        let tempDir = makeTempDirectory()

        let image1 = copyFixture(resource: "one-pixel", ext: "png", to: tempDir)
        let image2 = copyFixture(resource: "two-pixel", ext: "png", to: tempDir)
        let nonImage = tempDir.appendingPathComponent("notes.txt")
        let hiddenImage = tempDir.appendingPathComponent(".hidden.png")

        try? "hello".data(using: .utf8)?.write(to: nonImage)
        try? FileManager.default.copyItem(at: image1, to: hiddenImage)

        let nestedDir = tempDir.appendingPathComponent("nested", isDirectory: true)
        try? FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let nestedImage = copyFixture(resource: "one-pixel", ext: "png", to: nestedDir)

        sut.loadImages(from: tempDir)
        await waitForImagesLoaded(sut: sut)

        let loadedNames = Set(sut.images.map { $0.name })
        XCTAssertTrue(loadedNames.contains(image1.lastPathComponent))
        XCTAssertTrue(loadedNames.contains(image2.lastPathComponent))
        XCTAssertTrue(loadedNames.contains(nestedImage.lastPathComponent))
        XCTAssertFalse(loadedNames.contains(nonImage.lastPathComponent))
        XCTAssertFalse(loadedNames.contains(hiddenImage.lastPathComponent))
    }

    func testLoadImages_enumeratesAdvancedFormatsIncludingRawExtensions() async {
        let preferencesStore = InMemoryPreferencesStore()
        let sut = makeAppState(preferencesStore: preferencesStore)
        let tempDir = makeTempDirectory()

        let rawFilenames = ["sample.cr2", "sample.cr3", "sample.nef", "sample.arw", "sample.webp"]
        for filename in rawFilenames {
            let fileURL = tempDir.appendingPathComponent(filename)
            FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
        }

        let heicURL = TestFixtures.url(resource: "photo3", extension: "heic")
        let copiedHeicURL = tempDir.appendingPathComponent(heicURL.lastPathComponent)
        try? FileManager.default.copyItem(at: heicURL, to: copiedHeicURL)

        let tiffURL = TestFixtures.url(resource: "photo4", extension: "tiff")
        let copiedTiffURL = tempDir.appendingPathComponent(tiffURL.lastPathComponent)
        try? FileManager.default.copyItem(at: tiffURL, to: copiedTiffURL)

        sut.loadImages(from: tempDir)
        await waitForImagesLoaded(sut: sut)

        let loadedNames = Set(sut.images.map(\.name))
        XCTAssertTrue(loadedNames.contains("sample.cr2"))
        XCTAssertTrue(loadedNames.contains("sample.cr3"))
        XCTAssertTrue(loadedNames.contains("sample.nef"))
        XCTAssertTrue(loadedNames.contains("sample.arw"))
        XCTAssertTrue(loadedNames.contains("sample.webp"))
        XCTAssertTrue(loadedNames.contains("photo3.heic"))
        XCTAssertTrue(loadedNames.contains("photo4.tiff"))
    }

    func testLoadImages_folderSwitchClearsVisibleImagesBeforeNewFolderPublishes() async {
        let scanner = ControlledImageScanner()
        let sut = makeAppState(preferencesStore: InMemoryPreferencesStore(), imageScanner: scanner)
        let folderA = makeTempDirectory()
        let folderB = makeTempDirectory()
        let imageA = ImageFile(
            url: folderA.appendingPathComponent("first.jpg"),
            name: "first.jpg",
            creationDate: Date()
        )

        sut.loadImages(from: folderA)
        await scanner.waitUntilStarted(for: folderA)
        _ = await scanner.emitBatch(
            .init(images: [imageA], failedImages: [], isFinal: false),
            for: folderA
        )
        XCTAssertEqual(sut.images.map(\.name), ["first.jpg"])

        sut.loadImages(from: folderB)
        await scanner.waitUntilStarted(for: folderB)

        XCTAssertTrue(sut.images.isEmpty, "Switching folders should immediately clear the previous folder images")
        XCTAssertTrue(sut.isLoadingImages, "Switching folders should keep loading active until the new folder publishes")
        XCTAssertEqual(sut.selectedFolder?.standardizedFileURL, folderB.standardizedFileURL)
    }

    private func waitForImagesLoaded(sut: AppState, timeout: TimeInterval = 2.0) async {
        let expectation = XCTestExpectation(description: "Images loaded")
        Task {
            while true {
                if !sut.isLoadingImages {
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: timeout)
    }
}
