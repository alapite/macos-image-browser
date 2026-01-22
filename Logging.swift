import Foundation
import os

enum Logging {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "ImageBrowser"

    @available(macOS 12.0, *)
    static let scanSignposter = OSSignposter(logger: .scan)
}

extension Logger {
    static let scan = Logger(subsystem: Logging.subsystem, category: "scan")
    static let imageLoad = Logger(subsystem: Logging.subsystem, category: "imageLoad")
}
