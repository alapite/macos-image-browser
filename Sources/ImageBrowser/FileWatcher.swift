import Foundation
import Dispatch

enum FileEventType {
    case created
    case deleted
    case modified
}

struct FileEvent {
    let url: URL
    let type: FileEventType
}

protocol FileWatching: Actor {
    func startWatching(eventsHandler: @escaping @Sendable ([FileEvent]) async -> Void) async
    func stopWatching() async
}

actor FileWatcher: FileWatching {
    private let fileSystem: FileSystemProviding
    private let url: URL
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var eventHandler: (@Sendable ([FileEvent]) async -> Void)?
    private var previousFiles: Set<URL> = []

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp",
        "heic", "tiff", "webp",
        "cr2", "cr3", "nef", "arw"
    ]

    init(fileSystem: FileSystemProviding, url: URL) {
        self.fileSystem = fileSystem
        self.url = url
    }

    func startWatching(eventsHandler: @escaping @Sendable ([FileEvent]) async -> Void) async {
        guard dispatchSource == nil else { return }

        self.eventHandler = eventsHandler

        previousFiles = scanDirectory()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("Failed to open file descriptor for \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue(label: "com.imagebrowser.filewatcher", qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.handleFileSystemEvent()
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        self.dispatchSource = source
        source.resume()
    }

    func stopWatching() async {
        dispatchSource?.cancel()
        dispatchSource = nil
        eventHandler = nil
        previousFiles.removeAll()
    }

    private func handleFileSystemEvent() async {
        guard let eventHandler = eventHandler else { return }

        let currentFiles = scanDirectory()
        let previous = previousFiles
        previousFiles = currentFiles

        var events: [FileEvent] = []

        let addedFiles = currentFiles.subtracting(previous)
        for fileURL in addedFiles {
            events.append(FileEvent(url: fileURL, type: .created))
        }

        let deletedFiles = previous.subtracting(currentFiles)
        for fileURL in deletedFiles {
            events.append(FileEvent(url: fileURL, type: .deleted))
        }

        if !events.isEmpty {
            await eventHandler(events)
        }
    }

    private func scanDirectory() -> Set<URL> {
        var files: Set<URL> = []

        guard let enumerator = fileSystem.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard !isHiddenFile(fileURL) else { continue }
            guard isImageFile(fileURL) else { continue }

            files.insert(fileURL.standardizedFileURL)
        }

        return files
    }

    private func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func isHiddenFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }
}
