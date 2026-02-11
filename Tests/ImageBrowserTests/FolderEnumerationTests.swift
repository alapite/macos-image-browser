import XCTest
@testable import ImageBrowser

@MainActor
final class FolderEnumerationTests: XCTestCase {
    func testLoadImages_enumeratesSupportedImagesSkippingHiddenAndNonImages() async {
        let preferencesStore = InMemoryPreferencesStore()
        let sut = AppState(preferencesStore: preferencesStore)
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
