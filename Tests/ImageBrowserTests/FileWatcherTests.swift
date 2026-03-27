import Foundation
import XCTest
@testable import ImageBrowser

private func isImageFile(_ url: URL) -> Bool {
    let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff", "webp", "cr2", "cr3", "nef", "arw"]
    return imageExtensions.contains(url.pathExtension.lowercased())
}

@MainActor
final class FileWatcherTests: XCTestCase {

    var tempDirectory: URL!
    var fileSystem: LocalFileSystem!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = makeTempDirectory()
        fileSystem = LocalFileSystem()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    func testFileWatcherDetectsNewImageFiles() async throws {
        let expectation = XCTestExpectation(description: "FileWatcher detects new image")
        expectation.expectedFulfillmentCount = 3

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        _ = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)
        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)

        await fulfillment(of: [expectation], timeout: 2.0)

        await watcher.stopWatching()
    }

    func testFileWatcherDetectsDeletedFiles() async throws {
        let expectation = XCTestExpectation(description: "FileWatcher detects deleted file")

        let file1 = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .deleted {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        try FileManager.default.removeItem(at: file1)

        await fulfillment(of: [expectation], timeout: 2.0)

        await watcher.stopWatching()
    }

    func testFileWatcherDoesNotReportNonImageFiles() async throws {
        let expectation = XCTestExpectation(description: "Wait for non-image file creation")
        expectation.isInverted = true

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let textFile = tempDirectory.appendingPathComponent("test.txt")
        try "Some text".write(to: textFile, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 500_000_000)

        await fulfillment(of: [expectation], timeout: 1.0)

        await watcher.stopWatching()
    }

    func testFileWatcherCanStopAndRestartWatching() async throws {
        let firstExpectation = XCTestExpectation(description: "First watch session")
        let secondExpectation = XCTestExpectation(description: "Second watch session")

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    firstExpectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        _ = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)

        await fulfillment(of: [firstExpectation], timeout: 2.0)

        await watcher.stopWatching()

        try await Task.sleep(nanoseconds: 100_000_000)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    secondExpectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)

        await fulfillment(of: [secondExpectation], timeout: 2.0)

        await watcher.stopWatching()
    }

    func testFileWatcherHandlesMultipleEventsInBatch() async throws {
        let expectation = XCTestExpectation(description: "Detect multiple files")
        expectation.expectedFulfillmentCount = 5

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        for i in 1...5 {
            let sourceURL = TestFixtures.url(resource: "photo1", extension: "jpg")
            let destURL = tempDirectory.appendingPathComponent("image\(i).jpg")
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        await watcher.stopWatching()
    }

    func testFileWatcherIgnoresHiddenFiles() async throws {
        let expectation = XCTestExpectation(description: "Should detect visible file only")
        expectation.expectedFulfillmentCount = 1
        let hiddenExpectation = XCTestExpectation(description: "Hidden file should not be reported")
        hiddenExpectation.isInverted = true

        let watcher = FileWatcher(fileSystem: fileSystem, url: tempDirectory)

        await watcher.startWatching { events in
            for event in events {
                if event.type == .created && isImageFile(event.url) {
                    if event.url.lastPathComponent.hasPrefix(".") {
                        hiddenExpectation.fulfill()
                    } else {
                        expectation.fulfill()
                    }
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let hiddenSource = TestFixtures.url(resource: "photo1", extension: "jpg")
        let hiddenDest = tempDirectory.appendingPathComponent(".hidden.jpg")
        try? FileManager.default.removeItem(at: hiddenDest)
        try FileManager.default.copyItem(at: hiddenSource, to: hiddenDest)

        _ = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)

        await fulfillment(of: [expectation, hiddenExpectation], timeout: 2.0)

        await watcher.stopWatching()
    }
}
