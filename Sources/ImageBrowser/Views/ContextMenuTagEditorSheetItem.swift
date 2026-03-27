import SwiftUI

/// Sheet item for context menu tag editor
///
/// Wraps the target image URLs to enable proper SwiftUI sheet presentation timing.
struct ContextMenuTagEditorSheetItem: Identifiable {
    let id = UUID()
    let targetImageURLs: [String]

    init(targetImageURLs: [String]) {
        self.targetImageURLs = targetImageURLs
    }
}
