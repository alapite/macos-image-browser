import XCTest
@testable import ImageBrowser

final class ContextMenuTaggingModelTests: XCTestCase {
    func testResolveTargetImageURLs_usesSelectedRowsWhenClickedImageIsInSelection() {
        let clickedImage = makeImage(id: "image-1", url: "file:///tmp/image-1.jpg")
        let secondSelectedImage = makeImage(id: "image-2", url: "file:///tmp/image-2.jpg")
        let unrelatedImage = makeImage(id: "image-3", url: "file:///tmp/image-3.jpg")
        let allImages = [clickedImage, secondSelectedImage, unrelatedImage]

        let urls = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: clickedImage.id,
            selectedImageIDs: [clickedImage.id, secondSelectedImage.id],
            visibleImages: allImages
        )

        XCTAssertEqual(
            Set(urls),
            Set([
                clickedImage.url.standardizedFileURL.absoluteString,
                secondSelectedImage.url.standardizedFileURL.absoluteString
            ])
        )
    }

    func testResolveTargetImageURLs_fallsBackToClickedRowWhenNoSelection() {
        let clickedImage = makeImage(id: "image-10", url: "file:///tmp/image-10.jpg")
        let allImages = [clickedImage]

        let urls = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: clickedImage.id,
            selectedImageIDs: [],
            visibleImages: allImages
        )

        XCTAssertEqual(urls, [clickedImage.url.standardizedFileURL.absoluteString])
    }

    func testCommittedTags_normalizesDelimitedInputAndDeduplicatesCaseInsensitively() {
        let result = ContextMenuTaggingModel.committedTags(
            from: "  Travel, travel\nBeach,  BEACH  , city  ",
            existingTags: []
        )

        XCTAssertEqual(result, ["Travel", "Beach", "city"])
    }

    private func makeImage(id: String, url: String) -> DisplayImage {
        DisplayImage(
            id: id,
            url: URL(string: url)!,
            name: "\(id).jpg",
            creationDate: Date(timeIntervalSince1970: 0),
            rating: 0,
            isFavorite: false,
            fileSizeBytes: 1,
            fullIndex: 0,
            hasLoadError: false
        )
    }
}
