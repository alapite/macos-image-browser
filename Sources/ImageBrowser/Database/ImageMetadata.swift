import Foundation
import GRDB

/// Image metadata database record for persistence.
///
/// Conforms to GRDB's Codable record pattern for automatic SQL generation.
/// Uses struct for value semantics and immutability.
///
/// Note: Named `ImageMetadataRecord` to distinguish from the in-memory
/// `ImageMetadata` struct used in `ImageFile` for lazy loading.
public struct ImageMetadataRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    
    // MARK: - Properties
    
    /// File path as standardized URL string (primary key)
    public var url: String
    
    /// Rating from 0-5 stars (0 = unrated)
    public var rating: Int
    
    /// Favorite flag
    public var isFavorite: Bool

    /// Excluded flag used to hide images from browsing flows.
    public var isExcluded: Bool

    /// Timestamp of when the image was marked excluded.
    public var excludedAt: Date?
    
    /// First created timestamp
    public var createdAt: Date
    
    /// Last modified timestamp
    public var updatedAt: Date
    
    // MARK: - Initialization
    
    /// Initialize with explicit values (used for testing and manual creation)
    public init(
        url: String,
        rating: Int = 0,
        isFavorite: Bool = false,
        isExcluded: Bool = false,
        excludedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.url = url
        self.rating = rating
        self.isFavorite = isFavorite
        self.isExcluded = isExcluded
        self.excludedAt = excludedAt
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

extension ImageMetadataRecord: TableRecord {
    /// Table name in database
    public static let databaseTableName = "image_metadata"
}

// MARK: - PersistableRecord Conformance

extension ImageMetadataRecord {
    /// Encodes record to database row
    public func encode(to container: inout PersistenceContainer) throws {
        container["url"] = url
        container["rating"] = rating
        container["isFavorite"] = isFavorite
        container["isExcluded"] = isExcluded
        container["excludedAt"] = excludedAt
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

// MARK: - FetchableRecord Conformance

extension ImageMetadataRecord {
    /// Initializes record from database row
    public init(row: Row) throws {
        url = row["url"]
        rating = row["rating"]
        isFavorite = row["isFavorite"]
        isExcluded = row["isExcluded"]
        excludedAt = row["excludedAt"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }
}
