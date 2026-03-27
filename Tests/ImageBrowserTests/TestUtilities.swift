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

struct TestEnvironmentProvider: EnvironmentProviding {
    let environment: [String: String]

    init(environment: [String: String] = [:]) {
        self.environment = environment
    }
}

@MainActor
func makeAppStateDependencies(
    preferencesStore: PreferencesStore = InMemoryPreferencesStore(),
    fileSystem: FileSystemProviding = LocalFileSystem(),
    downsamplingPipeline: ImageDownsamplingProviding = ImageDownsamplingPipeline(thumbnailLimit: 1000),
    imageScanner: (any ImageDirectoryScanning)? = nil,
    imageCache: ImageCaching = NSImageCacheStore(totalCostLimit: 1024 * 1024 * 100, countLimit: 100),
    slideshowScheduler: SlideshowScheduling = TimerSlideshowScheduler(),
    environment: EnvironmentProviding = TestEnvironmentProvider(),
    fileWatcherFactory: (@Sendable (URL) -> any FileWatching)? = { watchURL in
        FileWatcher(fileSystem: LocalFileSystem(), url: watchURL)
    }
) -> AppStateDependencies {
    let resolvedFileSystem = fileSystem

    return AppStateDependencies(
        fileSystem: resolvedFileSystem,
        preferencesStore: preferencesStore,
        downsamplingPipeline: downsamplingPipeline,
        imageScanner: imageScanner ?? ImageDirectoryScanner(fileSystem: resolvedFileSystem),
        imageCache: imageCache,
        slideshowScheduler: slideshowScheduler,
        environment: environment,
        fileWatcherFactory: fileWatcherFactory
    )
}

@MainActor
func makeAppState(
    preferencesStore: PreferencesStore = InMemoryPreferencesStore(),
    fileSystem: FileSystemProviding = LocalFileSystem(),
    downsamplingPipeline: ImageDownsamplingProviding = ImageDownsamplingPipeline(thumbnailLimit: 1000),
    imageScanner: (any ImageDirectoryScanning)? = nil,
    imageCache: ImageCaching = NSImageCacheStore(totalCostLimit: 1024 * 1024 * 100, countLimit: 100),
    slideshowScheduler: SlideshowScheduling = TimerSlideshowScheduler(),
    environment: EnvironmentProviding = TestEnvironmentProvider(),
    fileWatcherFactory: (@Sendable (URL) -> any FileWatching)? = { watchURL in
        FileWatcher(fileSystem: LocalFileSystem(), url: watchURL)
    }
) -> AppState {
    AppState(
        dependencies: makeAppStateDependencies(
            preferencesStore: preferencesStore,
            fileSystem: fileSystem,
            downsamplingPipeline: downsamplingPipeline,
            imageScanner: imageScanner,
            imageCache: imageCache,
            slideshowScheduler: slideshowScheduler,
            environment: environment,
            fileWatcherFactory: fileWatcherFactory
        )
    )
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
        let sourceFixturesRoot = sourceRoot
            .appendingPathComponent("Tests/Fixtures", isDirectory: true)
        if let sourceFixturesURL = findFixture(named: filename, under: sourceFixturesRoot) {
            return sourceFixturesURL
        }
        let rootCandidates = [
            ProcessInfo.processInfo.environment["PROJECT_DIR"],
            ProcessInfo.processInfo.environment["SRCROOT"],
            FileManager.default.currentDirectoryPath
        ].compactMap { $0 }

        for root in rootCandidates {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            let fixturesRoot = rootURL.appendingPathComponent("Tests/Fixtures", isDirectory: true)
            if let fixturesURL = findFixture(named: filename, under: fixturesRoot) {
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

private func findFixture(named filename: String, under root: URL) -> URL? {
    guard FileManager.default.fileExists(atPath: root.path) else {
        return nil
    }

    if FileManager.default.fileExists(atPath: root.appendingPathComponent(filename).path) {
        return root.appendingPathComponent(filename)
    }

    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    while let candidate = enumerator?.nextObject() as? URL {
        guard candidate.lastPathComponent == filename else { continue }
        return candidate
    }

    return nil
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
