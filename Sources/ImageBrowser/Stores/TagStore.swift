import Foundation
import Combine
import GRDB

/// Tag management store for CRUD operations and autocomplete.
///
/// Responsibilities:
/// - Manage tag creation, deletion, and queries
/// - Provide tag list for autocomplete UI
/// - Associate/disassociate tags with images
/// - Observe database changes reactively via ValueObservation
///
/// Design principles:
/// - Max 10 @Published properties to prevent bloat
/// - @MainActor ensures UI updates on main thread (SwiftUI requirement)
/// - ValueObservation auto-triggers UI updates when database changes
/// - UPSERT pattern for tag creation (ignore duplicates)
@MainActor
final class TagStore: ObservableObject {

    // MARK: - Published Properties (max 10)

    /// All tag names for autocomplete UI (sorted alphabetically)
    @Published var allTags: [String] = []

    /// Incremented when image_tags table changes (triggers GalleryStore refresh)
    @Published var imageTagsVersion: Int = 0

    // MARK: - Private Properties

    /// Database pool for concurrent reads
    private let dbPool: DatabasePool

    /// Combine cancellables for observation subscriptions
    private var cancellables = Set<AnyCancellable>()

    nonisolated private static func canonicalImageURLKey(_ rawValue: String) -> String {
        if let parsed = URL(string: rawValue), parsed.isFileURL {
            return parsed.standardizedFileURL.absoluteString
        }
        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue).standardizedFileURL.absoluteString
        }
        return rawValue
    }

    nonisolated private static func lookupImageURLKeys(_ rawValue: String) -> [String] {
        let canonical = canonicalImageURLKey(rawValue)
        if canonical == rawValue {
            return [canonical]
        }
        return [canonical, rawValue]
    }

    // MARK: - Initialization

    /// Initialize store with database pool
    /// - Parameter dbPool: GRDB database pool for tag access
    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
        setupTagObservation()
        setupImageTagsObservation()
    }

    // MARK: - Database Observation

    /// Setup reactive database observation for automatic UI updates
    ///
    /// Uses GRDB's ValueObservation to track changes to the tags table.
    /// When tags are added/removed in the database, the allTags array is
    /// automatically refreshed, triggering SwiftUI re-renders.
    private func setupTagObservation() {
        let observation = ValueObservation.tracking { db in
            // Fetch all tag names from database, sorted alphabetically
            try TagRecord.fetchAll(db, sql: "SELECT * FROM tags ORDER BY name COLLATE NOCASE ASC")
                .map { $0.name }
        }

        // Observe changes via Combine publisher
        observation.publisher(in: dbPool)
            .receive(on: DispatchQueue.main)  // Ensure UI updates on main thread
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Log errors but don't crash - observation continues
                        print("⚠️ TagStore database observation error: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] tagNames in
                    // Update published property when database changes
                    self?.allTags = tagNames
                }
            )
            .store(in: &cancellables)
    }

    /// Setup reactive database observation for image_tags table
    ///
    /// Tracks changes to the image_tags junction table and triggers
    /// GalleryStore updates by incrementing imageTagsVersion.
    private func setupImageTagsObservation() {
        let observation = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM image_tags") ?? 0
        }

        observation.publisher(in: dbPool)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("⚠️ TagStore image_tags observation error: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.imageTagsVersion &+= 1
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Tag CRUD Operations

    /// Fetch all tag names from database
    /// - Returns: Array of tag names sorted alphabetically
    func fetchAllTags() async -> [String] {
        do {
            return try await dbPool.read { db in
                try TagRecord.fetchAll(db, sql: "SELECT * FROM tags ORDER BY name COLLATE NOCASE ASC")
                    .map { $0.name }
            }
        } catch {
            print("⚠️ Failed to fetch tags: \(error.localizedDescription)")
            return []
        }
    }

    /// Add a new tag to the database (UPSERT pattern)
    /// - Parameter name: Tag name to add
    ///
    /// If tag already exists (case-insensitive), this operation is ignored.
    func addTag(_ name: String) async throws {
        try await dbPool.write { db in
            let tag = TagRecord(name: name)
            try tag.insert(db)
        }
    }

    /// Remove a tag from the database
    /// - Parameter name: Tag name to remove
    ///
    /// CASCADE deletes all image_tags associations automatically.
    func removeTag(_ name: String) async throws {
        try await dbPool.write { db in
            _ = try TagRecord.filter(Column("name") == name).deleteAll(db)
        }
    }

    /// Rename an existing tag while preserving image associations
    /// - Parameters:
    ///   - from: Existing tag name
    ///   - to: New tag name
    ///
    /// Enforces case-insensitive uniqueness. Throws if source tag does not exist
    /// or destination conflicts with another existing tag.
    func renameTag(from sourceName: String, to destinationName: String) async throws {
        let source = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            throw DatabaseError(message: "Source tag cannot be empty")
        }
        guard !destination.isEmpty else {
            throw DatabaseError(message: "Destination tag cannot be empty")
        }

        try await dbPool.write { db in
            guard let sourceRow = try Row.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                arguments: [source]
            ) else {
                throw DatabaseError(message: "Tag not found: \(source)")
            }

            guard let sourceId: Int64 = sourceRow["id"] else {
                throw DatabaseError(message: "Invalid source tag id for: \(source)")
            }

            if let destinationRow = try Row.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                arguments: [destination]
            ) {
                let destinationId: Int64? = destinationRow["id"]
                if destinationId != sourceId {
                    throw DatabaseError(message: "Tag already exists: \(destination)")
                }
            }

            try db.execute(
                sql: "UPDATE tags SET name = ? WHERE id = ?",
                arguments: [destination, sourceId]
            )
        }
    }

    /// Merge one tag into another and remove the source tag
    /// - Parameters:
    ///   - source: Source tag name to merge from
    ///   - destination: Destination tag name to merge into
    ///
    /// Uses INSERT OR IGNORE semantics to avoid duplicate junction rows.
    func mergeTags(source sourceName: String, destination destinationName: String) async throws {
        let source = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            throw DatabaseError(message: "Source tag cannot be empty")
        }
        guard !destination.isEmpty else {
            throw DatabaseError(message: "Destination tag cannot be empty")
        }
        guard source.caseInsensitiveCompare(destination) != .orderedSame else {
            return
        }

        try await dbPool.write { db in
            guard let sourceId: Int64 = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                arguments: [source]
            ) else {
                throw DatabaseError(message: "Tag not found: \(source)")
            }

            guard let destinationId: Int64 = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                arguments: [destination]
            ) else {
                throw DatabaseError(message: "Tag not found: \(destination)")
            }

            try db.execute(
                sql: """
                INSERT OR IGNORE INTO image_tags (url, tagId)
                SELECT url, ?
                FROM image_tags
                WHERE tagId = ?
                """,
                arguments: [destinationId, sourceId]
            )

            try db.execute(
                sql: "DELETE FROM image_tags WHERE tagId = ?",
                arguments: [sourceId]
            )

            try db.execute(
                sql: "DELETE FROM tags WHERE id = ?",
                arguments: [sourceId]
            )
        }
    }

    // MARK: - Image Tag Association Operations

    /// Fetch all tags associated with an image (synchronous version)
    /// - Parameter imageUrl: URL string of the image
    /// - Returns: Set of tag names
    ///
    /// This is a synchronous wrapper around the async version for use in
    /// synchronous filter contexts. Prefer the async version when possible.
    func tagsForImageSync(_ imageUrl: String) -> Set<String> {
        let lookupKeys = Self.lookupImageURLKeys(imageUrl)
        do {
            return try dbPool.read { db in
                // Join image_tags with tags to get tag names
                let rows: [Row]
                if lookupKeys.count == 1 {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT tags.name
                        FROM tags
                        INNER JOIN image_tags ON tags.id = image_tags.tagId
                        WHERE image_tags.url = ?
                        ORDER BY tags.name ASC
                        """,
                        arguments: [lookupKeys[0]]
                    )
                } else {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT tags.name
                        FROM tags
                        INNER JOIN image_tags ON tags.id = image_tags.tagId
                        WHERE image_tags.url IN (?, ?)
                        ORDER BY tags.name ASC
                        """,
                        arguments: [lookupKeys[0], lookupKeys[1]]
                    )
                }
                return Set(rows.compactMap { $0["name"] as String? })
            }
        } catch {
            print("⚠️ Failed to fetch tags for image: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch all tags associated with an image
    /// - Parameter imageUrl: URL string of the image
    /// - Returns: Set of tag names
    func tagsForImage(_ imageUrl: String) async -> Set<String> {
        let lookupKeys = Self.lookupImageURLKeys(imageUrl)
        do {
            return try await dbPool.read { db in
                // Join image_tags with tags to get tag names
                let rows: [Row]
                if lookupKeys.count == 1 {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT tags.name
                        FROM tags
                        INNER JOIN image_tags ON tags.id = image_tags.tagId
                        WHERE image_tags.url = ?
                        ORDER BY tags.name ASC
                        """,
                        arguments: [lookupKeys[0]]
                    )
                } else {
                    rows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT tags.name
                        FROM tags
                        INNER JOIN image_tags ON tags.id = image_tags.tagId
                        WHERE image_tags.url IN (?, ?)
                        ORDER BY tags.name ASC
                        """,
                        arguments: [lookupKeys[0], lookupKeys[1]]
                    )
                }
                return Set(rows.compactMap { $0["name"] as String? })
            }
        } catch {
            print("⚠️ Failed to fetch tags for image: \(error.localizedDescription)")
            return []
        }
    }

    /// Add a tag to an image
    /// - Parameters:
    ///   - tag: Tag name to add
    ///   - imageUrl: URL string of the image
    ///
    /// Looks up tag ID by name and inserts into image_tags junction table.
    func addTagToImage(_ tag: String, for imageUrl: String) async throws {
        let canonicalImageURL = Self.canonicalImageURLKey(imageUrl)
        try await dbPool.write { db in
            // Look up tag ID by name
            guard let tagRecord = try TagRecord.filter(Column("name") == tag).fetchOne(db) else {
                // Tag doesn't exist, create it first
                let newTag = TagRecord(name: tag)
                try newTag.insert(db)
                guard let tagId = newTag.id else {
                    throw DatabaseError(message: "Failed to insert tag: \(tag)")
                }
                try db.execute(
                    sql: "INSERT INTO image_tags (url, tagId) VALUES (?, ?)",
                    arguments: [canonicalImageURL, tagId]
                )
                return
            }

            // Tag exists, insert association (ignore if already exists)
            guard let tagId = tagRecord.id else { return }
            try db.execute(
                sql: "INSERT OR IGNORE INTO image_tags (url, tagId) VALUES (?, ?)",
                arguments: [canonicalImageURL, tagId]
            )
        }
    }

    /// Remove a tag from an image
    /// - Parameters:
    ///   - tag: Tag name to remove
    ///   - imageUrl: URL string of the image
    func removeTagFromImage(_ tag: String, for imageUrl: String) async throws {
        let canonicalImageURL = Self.canonicalImageURLKey(imageUrl)
        try await dbPool.write { db in
            // Delete image_tags row where URL and tag name match
            try db.execute(
                sql: """
                DELETE FROM image_tags
                WHERE url = ?
                AND tagId = (SELECT id FROM tags WHERE name = ?)
                """,
                arguments: [canonicalImageURL, tag]
            )
        }
    }

    // MARK: - Batch Tag Operations

    /// Add multiple tags to multiple images in a single transaction
    /// - Parameters:
    ///   - tags: Set of tag names to add
    ///   - imageUrls: Array of image URL strings
    /// - Returns: Tuple with (successCount, failureCount)
    ///
    /// Uses database transaction for atomic all-or-nothing semantics.
    /// Creates tags automatically if they don't exist (idempotent).
    /// Skips non-existent images for partial success.
    func addTagsToImages(_ tags: Set<String>, to imageUrls: [String]) async throws -> (success: Int, failed: Int) {
        guard !tags.isEmpty && !imageUrls.isEmpty else {
            return (success: 0, failed: 0)
        }

        // Log batch operation for debugging
        print("🏷️ Batch tag apply: \(tags.count) tags to \(imageUrls.count) images")

        let result = try await dbPool.write { db -> (success: Int, failed: Int) in
            // Step 1: Ensure all tags exist and get their IDs
            // This must happen BEFORE linking to images to avoid FOREIGN KEY errors
            var tagIDs: [Int64] = []
            var createdTags = 0
            var successCount = 0

            for tag in tags {
                // Normalize tag name (trim whitespace, preserve case)
                let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)

                // Try to find existing tag (case-insensitive lookup to match database schema)
                if let existingTagID: Int64 = try Int64.fetchOne(
                    db,
                    sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                    arguments: [normalizedTag]
                ) {
                    tagIDs.append(existingTagID)
                } else {
                    // Create new tag within same transaction
                    // Use INSERT OR IGNORE to handle any race conditions
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO tags (name) VALUES (?)",
                        arguments: [normalizedTag]
                    )

                    // Fetch the ID we just inserted (now guaranteed to exist)
                    if let newTagID: Int64 = try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                        arguments: [normalizedTag]
                    ) {
                        tagIDs.append(newTagID)
                        createdTags += 1
                    } else {
                        // This shouldn't happen, but fail gracefully if it does
                        throw DatabaseError(message: "Failed to create tag: \(normalizedTag)")
                    }
                }
            }

            // Log tag creation
            if createdTags > 0 {
                print("  ✓ Created \(createdTags) new tags: \(tagIDs.count) total tags resolved")
            }

            // Step 2: Link all tags to all images
            var uniqueImageUrls: [String] = []
            var seenImageURLs: Set<String> = []
            for imageURL in imageUrls {
                let canonicalImageURL = Self.canonicalImageURLKey(imageURL)
                if seenImageURLs.insert(canonicalImageURL).inserted {
                    uniqueImageUrls.append(canonicalImageURL)
                }
            }

            for imageUrl in uniqueImageUrls {
                // Verify image exists in database, create if missing
                let imageExists: Bool = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM image_metadata WHERE url = ?)",
                    arguments: [imageUrl]
                ) ?? false

                if !imageExists {
                    // Auto-create metadata record for images not yet in database
                    // This can happen when images are scanned but not yet rated/favorited
                    print("  ⚠️ Image not in metadata table, auto-creating: \(imageUrl)")
                    let newRecord = ImageMetadataRecord(url: imageUrl)
                    try newRecord.insert(db)
                }

                // Link each tag to this image
                // INSERT OR IGNORE silently handles duplicates (UNIQUE constraint on url,tagId)
                var linkedForImage = 0
                for tagID in tagIDs {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO image_tags (url, tagId) VALUES (?, ?)",
                        arguments: [imageUrl, tagID]
                    )
                    let insertedRows = db.changesCount
                    linkedForImage += insertedRows
                    successCount += insertedRows
                }

                if linkedForImage > 0 {
                    let imageName = (imageUrl as NSString).lastPathComponent
                    print("  ✓ Linked \(linkedForImage) tags to \(imageName)")
                }
            }

            return (success: successCount, failed: 0)
        }

        print("  ✅ Batch complete: \(result.success) successful operations")
        return result
    }

    /// Remove multiple tags from multiple images in a single transaction
    /// - Parameters:
    ///   - tags: Set of tag names to remove
    ///   - imageUrls: Array of image URL strings
    /// - Returns: Tuple with (successCount, failureCount)
    ///
    /// Uses database transaction for all-or-nothing semantics.
    /// If any tag removal fails, the entire transaction is rolled back.
    func removeTagsFromImages(_ tags: Set<String>, from imageUrls: [String]) async throws -> (success: Int, failed: Int) {
        guard !tags.isEmpty && !imageUrls.isEmpty else {
            return (success: 0, failed: 0)
        }

        let successCount = try await dbPool.write { db -> Int in
            var writeCount = 0
            var uniqueImageUrls: [String] = []
            var seenImageURLs: Set<String> = []
            for imageURL in imageUrls {
                let canonicalImageURL = Self.canonicalImageURLKey(imageURL)
                if seenImageURLs.insert(canonicalImageURL).inserted {
                    uniqueImageUrls.append(canonicalImageURL)
                }
            }
            // Delete all specified tag-image combinations in a single transaction
            for imageUrl in uniqueImageUrls {
                for tag in tags {
                    // Delete image_tags row where URL and tag name match
                    try db.execute(
                        sql: """
                        DELETE FROM image_tags
                        WHERE url = ?
                        AND tagId = (SELECT id FROM tags WHERE name = ?)
                        """,
                        arguments: [imageUrl, tag]
                    )
                    writeCount += db.changesCount
                }
            }

            return writeCount
        }

        return (success: successCount, failed: 0)
    }
}

@MainActor
extension TagStore: AsyncImageTagLookupProviding {}

// MARK: - Error Types

extension TagStore {
    /// Tag insertion error
    struct DatabaseError: LocalizedError {
        let message: String

        var errorDescription: String? {
            return message
        }
    }
}
