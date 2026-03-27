import Foundation
import GRDB

// MARK: - SmartCollection Domain Model

/// Smart collection domain model for UI layer.
///
/// Separates database persistence logic from presentation layer.
/// Provides rule evaluation and image count computation.
///
/// This is the type used in SwiftUI views and stores - it's a lightweight
/// domain model that maps from SmartCollectionRecord (database) and includes
/// computed values like imageCount that are evaluated at initialization.
///
/// Marked @MainActor since it's used in SwiftUI views and calls @MainActor functions.
@MainActor
public struct SmartCollection: Identifiable {
    /// Collection ID (matches database primary key)
    public let id: Int64

    /// Collection name
    public let name: String

    /// Filter rules for this collection
    public let rules: CollectionRules

    /// Number of images matching the collection rules
    ///
    /// This is computed at initialization time by evaluating all images
    /// against the collection's rules. When images change, ValueObservation
    /// triggers re-evaluation and the collection is recreated with updated count.
    public let imageCount: Int

    /// Initialize from database record with image evaluation
    /// - Parameters:
    ///   - record: Database record to map from
    ///   - images: Array of images to evaluate against rules
    ///   - tagStore: Optional tag store for tag filtering
    @MainActor
    init(from record: SmartCollectionRecord, images: [ImageFile], tagStore: TagStore? = nil) {
        self.id = record.id ?? 0
        self.name = record.name
        self.rules = record.rules
        self.imageCount = evaluateImages(images, against: record.rules, tagStore: tagStore).count
    }
}
// MARK: - File-Level Helper Functions

/// Evaluate images against collection rules using AND or OR logic (synchronous version)
/// - Parameters:
///   - images: Array of images to evaluate
///   - rules: Collection rules to filter by
///   - tagStore: Optional tag store for tag-based filtering
/// - Returns: Filtered array of images matching the rules
///
/// If rules.matchAny is false (default): AND logic - all non-nil criteria must match
/// If rules.matchAny is true: OR logic - any non-nil criterion can match
@MainActor
internal func evaluateImages(
    _ images: [ImageFile],
    against rules: CollectionRules,
    tagStore: TagStore? = nil
) -> [ImageFile] {
    // Handle empty rules - match all images
    if rules.isEmpty {
        return images
    }

    // Branch based on matchAny
    if rules.matchAny {
        return evaluateMatchAny(images, rules, tagStore)
    } else {
        return evaluateMatchAll(images, rules, tagStore)
    }
}

/// Evaluate images using AND logic (Match All - all criteria must match)
@MainActor
private func evaluateMatchAll(
    _ images: [ImageFile],
    _ rules: CollectionRules,
    _ tagStore: TagStore?
) -> [ImageFile] {
    // Skip tag filter if no required tags specified
    guard let requiredTags = rules.requiredTags, !requiredTags.isEmpty else {
        // No tag filter - evaluate other criteria only
        return images.filter { image in
            // Check minimum rating filter
            if let minRating = rules.minimumRating {
                if image.rating < minRating {
                    return false
                }
            }

            // Check favorites filter
            if let favoritesOnly = rules.favoritesOnly {
                if image.isFavorite != favoritesOnly {
                    return false
                }
            }

            return true
        }
    }

    // Has tag filter - evaluate all criteria including tags using AND logic
    return images.filter { image in
        // Check minimum rating filter
        if let minRating = rules.minimumRating {
            if image.rating < minRating {
                return false
            }
        }

        // Check favorites filter
        if let favoritesOnly = rules.favoritesOnly {
            if image.isFavorite != favoritesOnly {
                return false
            }
        }

        // Check required tags filter using AND logic
        // All required tags must be present in the image's tags
        if let tagStore = tagStore {
            let imageTags = tagStore.tagsForImageSync(image.url.standardizedFileURL.absoluteString)
            if !requiredTags.isSubset(of: imageTags) {
                return false
            }
        }

        return true
    }
}

/// Evaluate images using OR logic (Match Any - any criterion can match)
@MainActor
private func evaluateMatchAny(
    _ images: [ImageFile],
    _ rules: CollectionRules,
    _ tagStore: TagStore?
) -> [ImageFile] {
    images.filter { image in
        var hasMatch = false

        // Check minimum rating filter
        if let minRating = rules.minimumRating {
            if image.rating >= minRating {
                hasMatch = true
            }
        }

        // Check favorites filter
        if let favoritesOnly = rules.favoritesOnly {
            if image.isFavorite == favoritesOnly {
                hasMatch = true
            }
        }

        // Check required tags filter using OR logic
        // Any required tag match counts (isDisjoint returns false if there's overlap)
        if let requiredTags = rules.requiredTags, !requiredTags.isEmpty {
            if let tagStore = tagStore {
                let imageTags = tagStore.tagsForImageSync(image.url.standardizedFileURL.absoluteString)
                if !requiredTags.isDisjoint(with: imageTags) {
                    hasMatch = true
                }
            }
        }

        return hasMatch
    }
}

// MARK: - Smart Collection Database Record

/// Smart collection database record for persistence.
///
/// Conforms to GRDB's Codable record pattern for automatic SQL generation.
/// Uses struct for value semantics and immutability.
///
/// Smart collections are saved filter rules that auto-update when images
/// are modified (via GRDB ValueObservation). The rules are stored as JSON
/// in the database for flexible filter criteria.
public struct SmartCollectionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {

    // MARK: - Properties

    /// Auto-incremented primary key
    public var id: Int64?

    /// Collection name (free-form text, unique constraint for user-friendly names)
    public var name: String

    /// Filter criteria for this collection (stored as JSON in database)
    public var rules: CollectionRules

    /// First created timestamp
    public var createdAt: Date

    /// Last modified timestamp
    public var updatedAt: Date

    // MARK: - Initialization

    /// Initialize with explicit values (used for testing and manual creation)
    public init(
        id: Int64? = nil,
        name: String,
        rules: CollectionRules,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rules = rules
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - GRDB Persistence Lifecycle

    /// Called before insert - set timestamps
    public mutating func willInsert(_ db: Database) throws {
        createdAt = Date()
        updatedAt = Date()
    }

    /// Called before update - update modified timestamp
    public mutating func willUpdate(_ db: Database) throws {
        updatedAt = Date()
    }
}

// MARK: - TableRecord Conformance

extension SmartCollectionRecord: TableRecord {
    /// Table name in database
    public static let databaseTableName = "smart_collections"
}

// MARK: - PersistableRecord Conformance

extension SmartCollectionRecord {
    /// Encodes record to database row
    ///
    /// CollectionRules is encoded to JSON for storage in the rules column.
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name

        // Encode CollectionRules to JSON for database storage
        let encoder = JSONEncoder()
        let rulesData = try encoder.encode(rules)
        container["rules"] = rulesData

        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

// MARK: - FetchableRecord Conformance

extension SmartCollectionRecord {
    /// Initializes record from database row
    ///
    /// CollectionRules is decoded from JSON stored in the rules column.
    public init(row: Row) throws {
        id = row["id"]
        name = row["name"]

        // Decode CollectionRules from JSON stored in database
        let rulesData: Data = row["rules"]
        let decoder = JSONDecoder()
        rules = try decoder.decode(CollectionRules.self, from: rulesData)

        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }
}
