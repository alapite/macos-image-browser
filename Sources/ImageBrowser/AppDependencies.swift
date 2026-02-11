import Foundation
import CoreGraphics

protocol FileSystemProviding {
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey],
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func fileExists(atPath path: String) -> Bool
}

struct LocalFileSystem: FileSystemProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey],
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path)
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
}

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
