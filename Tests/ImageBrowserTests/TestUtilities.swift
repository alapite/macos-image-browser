import Foundation
@testable import ImageBrowser

final class InMemoryPreferencesStore: PreferencesStore {
    private var storage: [String: Data] = [:]

    init() {}

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ data: Data, forKey key: String) {
        storage[key] = data
    }
}

enum TestFixtures {
    static func url(resource: String, extension ext: String) -> URL {
        let bundle = fixturesBundle()
        if let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: "Fixtures") {
            return url
        }
        if let url = bundle.url(forResource: resource, withExtension: ext) {
            return url
        }
        let filename = "\(resource).\(ext)"
        let sourceRoot = URL(fileURLWithPath: #file, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceFixturesURL = sourceRoot
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: sourceFixturesURL.path) {
            return sourceFixturesURL
        }
        let rootCandidates = [
            ProcessInfo.processInfo.environment["PROJECT_DIR"],
            ProcessInfo.processInfo.environment["SRCROOT"],
            FileManager.default.currentDirectoryPath
        ].compactMap { $0 }

        for root in rootCandidates {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            let fixturesURL = rootURL.appendingPathComponent("Tests/Fixtures", isDirectory: true)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fixturesURL.path) {
                return fixturesURL
            }
        }

        fatalError("Missing fixture \(resource).\(ext)")
    }
}

private final class FixturesBundleLocator {}

private func fixturesBundle() -> Bundle {
#if SWIFT_PACKAGE
    return Bundle.module
#else
    return Bundle(for: FixturesBundleLocator.self)
#endif
}

func makeTempDirectory() -> URL {
    let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let tempURL = baseURL.appendingPathComponent("ImageBrowserTests_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    return tempURL
}

func copyFixture(resource: String, ext: String, to directory: URL) -> URL {
    let sourceURL = TestFixtures.url(resource: resource, extension: ext)
    let destURL = directory.appendingPathComponent("\(resource).\(ext)")
    try? FileManager.default.removeItem(at: destURL)
    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
    return destURL
}
