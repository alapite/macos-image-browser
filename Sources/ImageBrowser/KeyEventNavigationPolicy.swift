import AppKit

enum KeyEventNavigationPolicy {
    static func shouldHandleArrowNavigation(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        firstResponder: NSResponder?
    ) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        if !modifierFlags.intersection(disallowedModifiers).isEmpty {
            return false
        }

        guard let firstResponder else {
            return true
        }

        if firstResponder is NSTextView {
            return false
        }

        // Keep up/down for native list movement while preserving left/right image navigation.
        if firstResponder is NSTableView {
            return keyCode == 123 || keyCode == 124
        }

        if firstResponder is NSControl {
            return false
        }

        return true
    }
}
