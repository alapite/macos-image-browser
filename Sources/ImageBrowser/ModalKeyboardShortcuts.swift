import SwiftUI

enum ModalKeyboardShortcutRole: Equatable {
    case cancelAction
    case defaultAction
}

enum ModalKeyboardShortcutAction {
    case smartCollectionCancel
    case smartCollectionSave
    case contextMenuTagEditorCancel
    case contextMenuTagEditorApply
}

enum ModalKeyboardShortcuts {
    static func role(for action: ModalKeyboardShortcutAction) -> ModalKeyboardShortcutRole {
        switch action {
        case .smartCollectionCancel, .contextMenuTagEditorCancel:
            return .cancelAction
        case .smartCollectionSave, .contextMenuTagEditorApply:
            return .defaultAction
        }
    }
}

extension View {
    @ViewBuilder
    func modalKeyboardShortcut(_ role: ModalKeyboardShortcutRole) -> some View {
        switch role {
        case .cancelAction:
            self.keyboardShortcut(.cancelAction)
        case .defaultAction:
            self.keyboardShortcut(.defaultAction)
        }
    }
}
