import XCTest
@testable import ImageBrowser

final class TagCommitParsingTests: XCTestCase {

    func testSingleTypedTagCommitsOnApply() {
        let result = TagCommitParser.committedTags(
            from: "vacation",
            existingTags: []
        )

        XCTAssertEqual(result, ["vacation"])
    }

    func testCommaSeparatedTagsCommitAsNormalizedSet() {
        let result = TagCommitParser.committedTags(
            from: "vacation, beach",
            existingTags: []
        )

        XCTAssertEqual(result, ["vacation", "beach"])
    }

    func testEmptyAndWhitespaceTokensAreIgnored() {
        let result = TagCommitParser.committedTags(
            from: "  vacation , ,   beach  ,   ",
            existingTags: []
        )

        XCTAssertEqual(result, ["vacation", "beach"])
    }

    func testExistingTagsPreservedAndCaseInsensitiveDuplicatesDeduplicated() {
        let result = TagCommitParser.committedTags(
            from: "VACATION, beach,  ",
            existingTags: ["vacation", "City"]
        )

        XCTAssertEqual(result, ["vacation", "City", "beach"])
    }
}
