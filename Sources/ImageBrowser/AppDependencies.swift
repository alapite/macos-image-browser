import Foundation
import CoreGraphics
import AppKit

protocol FileSystemProviding: Sendable {
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey],
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func fileExists(atPath path: String) -> Bool
}

struct LocalFileSystem: FileSystemProviding, Sendable {
    init() {}

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey],
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

protocol EnvironmentProviding {
    var environment: [String: String] { get }
}

extension ProcessInfo: EnvironmentProviding {}

protocol PreferencesStore {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

enum DownsamplingCacheKind {
    case thumbnail
    case main
}

protocol ImageDownsamplingProviding: Actor {
    func loadImage(from url: URL, maxPixelSize: Int, cache: DownsamplingCacheKind) async -> CGImage?
}

protocol ImageCaching {
    func image(forKey key: NSString) -> NSImage?
    func setImage(_ image: NSImage, forKey key: NSString, cost: Int)
}

final class NSImageCacheStore: ImageCaching {
    private let cache = NSCache<NSString, NSImage>()

    init(totalCostLimit: Int, countLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func image(forKey key: NSString) -> NSImage? {
        cache.object(forKey: key)
    }

    func setImage(_ image: NSImage, forKey key: NSString, cost: Int) {
        cache.setObject(image, forKey: key, cost: cost)
    }
}

protocol SlideshowTimer {
    func invalidate()
}

protocol SlideshowScheduling {
    @MainActor
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SlideshowTimer
}

private final class ScheduledTimerHandle: SlideshowTimer {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

struct TimerSlideshowScheduler: SlideshowScheduling {
    @MainActor
    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SlideshowTimer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                action()
            }
        }
        return ScheduledTimerHandle(timer: timer)
    }
}

struct UserDefaultsPreferencesStore: PreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

final class VolatilePreferencesStore: PreferencesStore {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ data: Data, forKey key: String) {
        storage[key] = data
    }
}
