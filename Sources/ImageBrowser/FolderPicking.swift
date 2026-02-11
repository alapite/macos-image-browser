import AppKit
import Foundation

enum FolderPicking {
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }
}
