import Foundation
import GRDB

/// Tag database record for persistence.
///
/// Conforms to GRDB's Codable record pattern for automatic SQL generation.
/// Uses struct for value semantics and immutability.
///
/// Table mapping:
/// - `tags` table with columns: id (auto-increment primary key), name (unique, not null)
/// - Case-insensitive uniqueness enforced by database index with COLLATE NOCASE
public struct TagRecord: Codable, FetchableRecord, PersistableRecord {

    // MARK: - Properties

    /// Auto-incremented primary key
    public var id: Int64?

    /// Tag name (unique, case-insensitive)
    public var name: String

    // MARK: - Initialization

    /// Initialize with explicit values (used for testing and manual creation)
    public init(
        id: Int64? = nil,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

// MARK: - TableRecord Conformance

extension TagRecord: TableRecord {
    /// Table name in database
    public static let databaseTableName = "tags"
}

// MARK: - PersistableRecord Conformance

extension TagRecord {
    /// Encodes record to database row
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
    }
}

// MARK: - FetchableRecord Conformance

extension TagRecord {
    /// Initializes record from database row
    public init(row: Row) throws {
        id = row["id"]
        name = row["name"]
    }
}
