import XCTest
@testable import ImageBrowser

final class ImageDownsamplingPipelineTests: XCTestCase {
    func testLoadImage_coalescesConcurrentRequestsForSameURLSizeAndCache() async {
        let counter = DecodeCounter()
        let pipeline = ImageDownsamplingPipeline(
            thumbnailLimit: 100,
            decode: { _, _ in
                await counter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return nil
            }
        )
        let url = URL(fileURLWithPath: "/tmp/coalesced.jpg")

        async let first = pipeline.loadImage(from: url, maxPixelSize: 2048, cache: .main)
        async let second = pipeline.loadImage(from: url, maxPixelSize: 2048, cache: .main)
        _ = await (first, second)

        let decodeCount = await counter.value
        XCTAssertEqual(decodeCount, 1, "Concurrent identical main-image requests should share a single decode")
    }

    func testLoadImage_doesNotCoalesceAcrossDifferentSizes() async {
        let counter = DecodeCounter()
        let pipeline = ImageDownsamplingPipeline(
            thumbnailLimit: 100,
            decode: { _, _ in
                await counter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return nil
            }
        )
        let url = URL(fileURLWithPath: "/tmp/unshared.jpg")

        async let first = pipeline.loadImage(from: url, maxPixelSize: 2048, cache: .main)
        async let second = pipeline.loadImage(from: url, maxPixelSize: 2304, cache: .main)
        _ = await (first, second)

        let decodeCount = await counter.value
        XCTAssertEqual(decodeCount, 2, "Different request sizes should remain independent decode work")
    }
}

private actor DecodeCounter {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}
