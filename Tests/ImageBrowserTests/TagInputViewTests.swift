import XCTest
@testable import ImageBrowser

/// Tests for free-text tag commit behavior in ContextMenuTagEditor
///
/// These tests verify that users can type new tags and press Enter to add them,
/// type comma-separated tags to parse multiple selections, and that the Apply
/// button enables when free-text tags are entered.
///
/// Plan 11-16 originally targeted TagInputView, but that component was removed
/// in plan 11-15 and replaced with ContextMenuTagEditor. The functionality
/// described in plan 11-16 (free-text tag commit on Enter/comma/apply) was
/// already implemented in ContextMenuTagger.swift.
final class TagInputViewTests: XCTestCase {
    // MARK: - Test 1: Enter key commits free-text tags

    func testFreeTextTagCommitOnSubmit() {
        // Given: User types a new tag not in existing suggestions
        let inputText = "sunset"
        let existingTags = Set<String>()

        // When: User presses Enter (onSubmit triggered)
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: Typed tag is added to selectedTags
        XCTAssertTrue(result.contains("sunset"), "Typed tag should be committed to selected tags")
        XCTAssertEqual(result.count, 1, "Exactly one tag should be added")
    }

    func testFreeTextTagCommitOnSubmit_withMultipleTags() {
        // Given: User types multiple tags separated by comma and newline
        let inputText = "nature,landscape\nurban"
        let existingTags = Set<String>()

        // When: User presses Enter
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: All tags are committed
        XCTAssertTrue(result.contains("nature"), "First tag should be committed")
        XCTAssertTrue(result.contains("landscape"), "Second tag should be committed")
        XCTAssertTrue(result.contains("urban"), "Third tag should be committed")
        XCTAssertEqual(result.count, 3, "All three tags should be added")
    }

    // MARK: - Test 2: Comma-separated tag parsing

    func testCommaSeparatedTagParsing() {
        // Given: User types comma-separated tags
        let inputText = "nature, landscape, city"
        let existingTags = Set<String>()

        // When: Tags are parsed
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: Tags are split and added individually
        XCTAssertTrue(result.contains("nature"), "Tag 1 should be parsed")
        XCTAssertTrue(result.contains("landscape"), "Tag 2 should be parsed")
        XCTAssertTrue(result.contains("city"), "Tag 3 should be parsed")
        XCTAssertEqual(result.count, 3, "All comma-separated tags should be added")
    }

    func testCommaSeparatedTagParsing_trimsWhitespace() {
        // Given: User types tags with irregular spacing
        let inputText = "  nature  ,  landscape  ,city"
        let existingTags = Set<String>()

        // When: Tags are parsed
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: Whitespace is trimmed from each tag
        XCTAssertTrue(result.contains("nature"), "Tag should be trimmed")
        XCTAssertTrue(result.contains("landscape"), "Tag should be trimmed")
        XCTAssertTrue(result.contains("city"), "Tag should be trimmed")
        XCTAssertEqual(result.count, 3, "All tags should be trimmed and added")
    }

    func testCommaSeparatedTagParsing_filtersEmptyStrings() {
        // Given: User types input with empty segments
        let inputText = "nature, , landscape,, city"
        let existingTags = Set<String>()

        // When: Tags are parsed
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: Empty strings are filtered out
        XCTAssertTrue(result.contains("nature"), "Valid tag should be included")
        XCTAssertTrue(result.contains("landscape"), "Valid tag should be included")
        XCTAssertTrue(result.contains("city"), "Valid tag should be included")
        XCTAssertEqual(result.count, 3, "Only non-empty tags should be added")
    }

    func testCommaSeparatedTagParsing_avoidsDuplicates() {
        // Given: User types duplicate tags (case-insensitive)
        let inputText = "nature, Nature, NATURE"
        let existingTags = Set<String>()

        // When: Tags are parsed
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: Duplicates are avoided (case-insensitive)
        XCTAssertEqual(result.count, 1, "Only one instance of tag should be added")
        XCTAssertTrue(result.contains("nature"), "First occurrence should be preserved")
    }

    func testCommaSeparatedTagParsing_mergesWithExisting() {
        // Given: User already has selected tags
        let existingTags = Set(["existing1", "existing2"])
        let inputText = "nature, landscape"

        // When: New tags are parsed
        let result = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: existingTags
        )

        // Then: New tags are merged with existing
        XCTAssertTrue(result.contains("existing1"), "Existing tag 1 should remain")
        XCTAssertTrue(result.contains("existing2"), "Existing tag 2 should remain")
        XCTAssertTrue(result.contains("nature"), "New tag 1 should be added")
        XCTAssertTrue(result.contains("landscape"), "New tag 2 should be added")
        XCTAssertEqual(result.count, 4, "All tags should be present")
    }

    // MARK: - Test 3: Apply button enabled with free-text

    func testApplyEnabledWithFreeText() {
        // Note: This test documents the expected behavior.
        // The actual UI binding logic is in ContextMenuTagEditor.swift line 64:
        // .disabled(selectedTags.isEmpty && !hasPendingInput)
        //
        // The hasPendingInput computed property (line 23-25) checks:
        // !ContextMenuTaggingModel.committedTags(from: inputText, existingTags: []).isEmpty
        //
        // This means Apply is enabled when:
        // - selectedTags is NOT empty, OR
        // - inputText contains tags that would be committed (hasPendingInput is true)

        // Given: User types free-text tags
        let inputText = "nature"

        // When: Check if pending input exists
        let pendingTags = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: []
        )

        // Then: Apply should be enabled (hasPendingInput would be true)
        XCTAssertFalse(pendingTags.isEmpty, "Free-text input should produce pending tags")
    }

    func testApplyEnabledWithFreeText_commaSeparated() {
        // Given: User types comma-separated tags
        let inputText = "nature, landscape, city"

        // When: Check if pending input exists
        let pendingTags = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: []
        )

        // Then: Apply should be enabled
        XCTAssertFalse(pendingTags.isEmpty, "Comma-separated input should produce pending tags")
        XCTAssertEqual(pendingTags.count, 3, "All tags should be recognized as pending")
    }

    func testApplyDisabledWithEmptyInput() {
        // Given: No tags selected and empty input
        let inputText = ""
        let selectedTags = Set<String>()

        // When: Check if pending input exists
        let pendingTags = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: selectedTags
        )

        // Then: Apply should be disabled
        XCTAssertTrue(pendingTags.isEmpty, "Empty input should not enable Apply")
    }

    func testApplyDisabledWithWhitespaceOnly() {
        // Given: Only whitespace input
        let inputText = "   "

        // When: Check if pending input exists
        let pendingTags = ContextMenuTaggingModel.committedTags(
            from: inputText,
            existingTags: []
        )

        // Then: Apply should be disabled (whitespace is trimmed)
        XCTAssertTrue(pendingTags.isEmpty, "Whitespace-only input should not enable Apply")
    }
}
