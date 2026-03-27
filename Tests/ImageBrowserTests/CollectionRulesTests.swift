import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class CollectionRulesTests: XCTestCase {

    // MARK: - JSON Encoding/Decoding Tests

    func testCollectionRulesEncodesToJSON() throws {
        // Arrange
        let rules = CollectionRules(
            minimumRating: 4,
            favoritesOnly: true,
            requiredTags: Set(["vacation", "beach"])
        )
        let encoder = JSONEncoder()

        // Act
        let jsonData = try encoder.encode(rules)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Assert
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("minimumRating"))
        XCTAssertTrue(jsonString!.contains("favoritesOnly"))
        XCTAssertTrue(jsonString!.contains("requiredTags"))
    }

    func testCollectionRulesDecodesFromJSON() throws {
        // Arrange
        let jsonString = """
        {
            "minimumRating": 3,
            "favoritesOnly": false,
            "requiredTags": ["sunset", "landscape"]
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        // Act
        let rules = try decoder.decode(CollectionRules.self, from: jsonData)

        // Assert
        XCTAssertEqual(rules.minimumRating, 3)
        XCTAssertEqual(rules.favoritesOnly, false)
        XCTAssertEqual(rules.requiredTags, Set(["sunset", "landscape"]))
        XCTAssertEqual(rules.matchAny, false)
    }

    func testCollectionRulesDecodesLegacyJSONWithoutMatchAny() throws {
        // Arrange
        let jsonString = """
        {
            "minimumRating": 4,
            "favoritesOnly": true,
            "requiredTags": ["travel"]
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let rules = try JSONDecoder().decode(CollectionRules.self, from: jsonData)

        // Assert
        XCTAssertEqual(rules.minimumRating, 4)
        XCTAssertEqual(rules.favoritesOnly, true)
        XCTAssertEqual(rules.requiredTags, Set(["travel"]))
        XCTAssertFalse(rules.matchAny)
    }

    func testCollectionRulesDecodesExplicitMatchAnyValues() throws {
        // Arrange
        let trueJSON = """
        {
            "matchAny": true
        }
        """
        let falseJSON = """
        {
            "matchAny": false
        }
        """

        // Act
        let matchAnyTrue = try JSONDecoder().decode(CollectionRules.self, from: Data(trueJSON.utf8))
        let matchAnyFalse = try JSONDecoder().decode(CollectionRules.self, from: Data(falseJSON.utf8))

        // Assert
        XCTAssertTrue(matchAnyTrue.matchAny)
        XCTAssertFalse(matchAnyFalse.matchAny)
    }

    func testCollectionRulesEncodeDecodeRoundTripPreservesMatchAny() throws {
        // Arrange
        let original = CollectionRules(
            minimumRating: 2,
            favoritesOnly: true,
            requiredTags: Set(["family", "portrait"]),
            matchAny: true
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CollectionRules.self, from: data)

        // Assert
        XCTAssertEqual(decoded.minimumRating, original.minimumRating)
        XCTAssertEqual(decoded.favoritesOnly, original.favoritesOnly)
        XCTAssertEqual(decoded.requiredTags, original.requiredTags)
        XCTAssertEqual(decoded.matchAny, original.matchAny)
    }

    // MARK: - Property Tests

    func testMinimumRatingProperty() {
        // Arrange & Act
        let rulesWithRating = CollectionRules(minimumRating: 5, favoritesOnly: nil, requiredTags: nil)
        let rulesWithoutRating = CollectionRules(minimumRating: nil, favoritesOnly: true, requiredTags: nil)

        // Assert
        XCTAssertEqual(rulesWithRating.minimumRating, 5)
        XCTAssertNil(rulesWithoutRating.minimumRating)
    }

    func testFavoritesOnlyProperty() {
        // Arrange & Act
        let rulesWithFavorites = CollectionRules(minimumRating: nil, favoritesOnly: true, requiredTags: nil)
        let rulesWithoutFavorites = CollectionRules(minimumRating: 4, favoritesOnly: nil, requiredTags: nil)

        // Assert
        XCTAssertEqual(rulesWithFavorites.favoritesOnly, true)
        XCTAssertNil(rulesWithoutFavorites.favoritesOnly)
    }

    func testRequiredTagsProperty() {
        // Arrange & Act
        let rulesWithTags = CollectionRules(minimumRating: nil, favoritesOnly: nil, requiredTags: Set(["photo", "album"]))
        let rulesWithoutTags = CollectionRules(minimumRating: 2, favoritesOnly: true, requiredTags: nil)

        // Assert
        XCTAssertEqual(rulesWithTags.requiredTags, Set(["photo", "album"]))
        XCTAssertNil(rulesWithoutTags.requiredTags)
    }

    // MARK: - AND Logic Tests

    func testAllNilRulesMatchAllImages() {
        // Arrange
        let rules = CollectionRules(minimumRating: nil, favoritesOnly: nil, requiredTags: nil)

        // Act & Assert
        // Empty rules should match all images (isEmpty == true)
        XCTAssertTrue(rules.isEmpty)
    }

    func testNonNilRulesHaveNonEmptyCriteria() {
        // Arrange & Act
        let rulesWithRating = CollectionRules(minimumRating: 3, favoritesOnly: nil, requiredTags: nil)
        let rulesWithFavorites = CollectionRules(minimumRating: nil, favoritesOnly: true, requiredTags: nil)
        let rulesWithTags = CollectionRules(minimumRating: nil, favoritesOnly: nil, requiredTags: Set(["test"]))
        let rulesWithAll = CollectionRules(minimumRating: 4, favoritesOnly: true, requiredTags: Set(["vacation"]))

        // Assert
        XCTAssertFalse(rulesWithRating.isEmpty)
        XCTAssertFalse(rulesWithFavorites.isEmpty)
        XCTAssertFalse(rulesWithTags.isEmpty)
        XCTAssertFalse(rulesWithAll.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyRequiredTagsSet() {
        // Arrange & Act
        let rules = CollectionRules(minimumRating: nil, favoritesOnly: nil, requiredTags: Set())

        // Assert
        // Empty set should be treated as no filter (nil)
        // For implementation simplicity, we may treat empty set as nil
        XCTAssertNotNil(rules.requiredTags)
        XCTAssertTrue(rules.requiredTags!.isEmpty)
    }

    func testZeroMinimumRating() {
        // Arrange & Act
        let rules = CollectionRules(minimumRating: 0, favoritesOnly: nil, requiredTags: nil)

        // Assert
        XCTAssertEqual(rules.minimumRating, 0)
        // 0 rating means "no minimum" in some implementations,
        // but here we use nil for no filter
        XCTAssertFalse(rules.isEmpty)
    }
}
