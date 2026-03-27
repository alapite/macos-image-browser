import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class SmartCollectionTests: XCTestCase {

    // MARK: - SmartCollection Properties Tests

    func testSmartCollectionHasIdProperty() throws {
        // Arrange
        let record = SmartCollectionRecord(
            id: 1,
            name: "Test Collection",
            rules: CollectionRules(minimumRating: 4),
            createdAt: Date(),
            updatedAt: Date()
        )
        let images = createTestImages(count: 5)

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.id, 1, "SmartCollection should have id property")
    }

    func testSmartCollectionHasNameProperty() throws {
        // Arrange
        let record = SmartCollectionRecord(
            id: 1,
            name: "My Favorites",
            rules: CollectionRules(),
            createdAt: Date(),
            updatedAt: Date()
        )
        let images = createTestImages(count: 3)

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.name, "My Favorites", "SmartCollection should have name property")
    }

    func testSmartCollectionHasRulesProperty() throws {
        // Arrange
        let rules = CollectionRules(minimumRating: 5, favoritesOnly: true)
        let record = SmartCollectionRecord(
            id: 1,
            name: "5-Star Favorites",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        let images = createTestImages(count: 2)

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.rules.minimumRating, 5, "SmartCollection should preserve minimumRating")
        XCTAssertEqual(collection.rules.favoritesOnly, true, "SmartCollection should preserve favoritesOnly")
    }

    // MARK: - Image Count Evaluation Tests

    func testImageCountWithMinimumRatingFilter() throws {
        // Arrange
        let rules = CollectionRules(minimumRating: 4)
        let record = SmartCollectionRecord(
            id: 1,
            name: "4+ Stars",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        var images = createTestImages(count: 5)
        // Set ratings: 0, 1, 2, 3, 4
        // Only index 4 (rating 4) should match rating >= 4
        for (index, image) in images.enumerated() {
            let metadata = ImageMetadata(rating: index, isFavorite: false)
            images[index] = ImageFile(
                url: image.url,
                name: image.name,
                creationDate: image.creationDate,
                fileSizeBytes: image.fileSizeBytes,
                metadata: metadata
            )
        }

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.imageCount, 1, "Should match images with rating >= 4")
    }

    func testImageCountWithFavoritesOnlyFilter() throws {
        // Arrange
        let rules = CollectionRules(favoritesOnly: true)
        let record = SmartCollectionRecord(
            id: 1,
            name: "All Favorites",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        var images = createTestImages(count: 4)
        // Mark first 2 as favorites
        for (index, image) in images.enumerated() {
            let metadata = ImageMetadata(rating: 0, isFavorite: index < 2)
            images[index] = ImageFile(
                url: image.url,
                name: image.name,
                creationDate: image.creationDate,
                fileSizeBytes: image.fileSizeBytes,
                metadata: metadata
            )
        }

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.imageCount, 2, "Should match favorited images")
    }

    func testImageCountWithRequiredTagsFilter() throws {
        // Arrange
        let rules = CollectionRules(requiredTags: Set(["vacation", "beach"]))
        let record = SmartCollectionRecord(
            id: 1,
            name: "Vacation Beach",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        var images = createTestImages(count: 3)
        // First image has both tags, second has only one, third has neither
        // Note: ImageFile doesn't have tags property yet, so this test will be updated when tags are implemented
        let metadata1 = ImageMetadata(rating: 0, isFavorite: false)
        let metadata2 = ImageMetadata(rating: 0, isFavorite: false)
        let metadata3 = ImageMetadata(rating: 0, isFavorite: false)

        images[0] = ImageFile(
            url: images[0].url,
            name: images[0].name,
            creationDate: images[0].creationDate,
            fileSizeBytes: images[0].fileSizeBytes,
            metadata: metadata1
        )
        images[1] = ImageFile(
            url: images[1].url,
            name: images[1].name,
            creationDate: images[1].creationDate,
            fileSizeBytes: images[1].fileSizeBytes,
            metadata: metadata2
        )
        images[2] = ImageFile(
            url: images[2].url,
            name: images[2].name,
            creationDate: images[2].creationDate,
            fileSizeBytes: images[2].fileSizeBytes,
            metadata: metadata3
        )

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        // For now, tags don't exist on ImageFile, so all images will match
        XCTAssertEqual(collection.imageCount, 3, "Tags not implemented yet, should match all")
    }

    func testImageCountWithMultipleFiltersANDLogic() throws {
        // Arrange
        let rules = CollectionRules(minimumRating: 4, favoritesOnly: true)
        let record = SmartCollectionRecord(
            id: 1,
            name: "4+ Star Favorites",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        var images = createTestImages(count: 5)
        // Create mix of ratings and favorites
        // Image 0: rating 5, favorite -> should match
        // Image 1: rating 4, favorite -> should match
        // Image 2: rating 5, not favorite -> should NOT match
        // Image 3: rating 3, favorite -> should NOT match
        // Image 4: rating 2, not favorite -> should NOT match
        let testCases: [(rating: Int, isFavorite: Bool)] = [
            (5, true), (4, true), (5, false), (3, true), (2, false)
        ]
        for (index, testCase) in testCases.enumerated() {
            let metadata = ImageMetadata(rating: testCase.rating, isFavorite: testCase.isFavorite)
            images[index] = ImageFile(
                url: images[index].url,
                name: images[index].name,
                creationDate: images[index].creationDate,
                fileSizeBytes: images[index].fileSizeBytes,
                metadata: metadata
            )
        }

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.imageCount, 2, "Should match images with BOTH rating >= 4 AND favorite=true")
    }

    func testImageCountWithEmptyRules() throws {
        // Arrange
        let rules = CollectionRules() // All nil
        let record = SmartCollectionRecord(
            id: 1,
            name: "All Images",
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )
        let images = createTestImages(count: 7)

        // Act
        let collection = SmartCollection(from: record, images: images)

        // Assert
        XCTAssertEqual(collection.imageCount, 7, "Empty rules should match all images")
    }

    // MARK: - Helper Methods

    private func createTestImages(count: Int) -> [ImageFile] {
        (0..<count).map { index in
            let url = URL(fileURLWithPath: "/tmp/test\(index).jpg")
            return ImageFile(
                url: url,
                name: "test\(index).jpg",
                creationDate: Date(),
                fileSizeBytes: Int64(index * 1_000_000)
            )
        }
    }
}
