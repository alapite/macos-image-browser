import XCTest
@testable import ImageBrowser

final class ModalKeyboardShortcutsTests: XCTestCase {
    func testSmartCollectionCancel_usesCancelActionShortcutRole() {
        XCTAssertEqual(
            ModalKeyboardShortcuts.role(for: .smartCollectionCancel),
            .cancelAction
        )
    }

    func testSmartCollectionSave_usesDefaultActionShortcutRole() {
        XCTAssertEqual(
            ModalKeyboardShortcuts.role(for: .smartCollectionSave),
            .defaultAction
        )
    }

    func testContextMenuTagEditorCancel_usesCancelActionShortcutRole() {
        XCTAssertEqual(
            ModalKeyboardShortcuts.role(for: .contextMenuTagEditorCancel),
            .cancelAction
        )
    }

    func testContextMenuTagEditorApply_usesDefaultActionShortcutRole() {
        XCTAssertEqual(
            ModalKeyboardShortcuts.role(for: .contextMenuTagEditorApply),
            .defaultAction
        )
    }
}
