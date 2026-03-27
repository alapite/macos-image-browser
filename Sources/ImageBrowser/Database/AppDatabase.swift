import Foundation
import GRDB

struct AppDatabaseConfiguration {
    let overridePath: String?
    let resetOnLaunch: Bool

    static func from(environment: [String: String]) -> AppDatabaseConfiguration {
        AppDatabaseConfiguration(
            overridePath: environment["IMAGEBROWSER_TEST_DB_PATH"],
            resetOnLaunch: environment["IMAGEBROWSER_RESET_DB"] == "1"
        )
    }
}

/// Database manager for image metadata persistence.
///
/// Provides a shared `DatabasePool` instance for concurrent read access,
/// with automatic schema migrations and WAL mode enabled for performance.
public final class AppDatabase {

    /// Database pool for concurrent reads
    public let dbPool: DatabasePool

    init(
        configuration: AppDatabaseConfiguration,
        fileManager: FileManager = .default
    ) {
        let dbURL = Self.databaseURL(configuration: configuration, fileManager: fileManager)

        if configuration.resetOnLaunch {
            Self.removeDatabaseArtifacts(at: dbURL, fileManager: fileManager)
        }
        
        // Configure database pool with WAL mode
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for concurrent read access
            try db.execute(sql: "PRAGMA journal_mode=WAL")
        }
        
        // Create database pool
        do {
            dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        } catch {
            fatalError("Failed to create database pool at \(dbURL.path): \(error)")
        }
        
        // Run migrations
        do {
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Migration failed: \(error)")
        }
    }

    private static func databaseURL(
        configuration: AppDatabaseConfiguration,
        fileManager: FileManager
    ) -> URL {
        if let overridePath = configuration.overridePath, !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath)
            let directoryURL = overrideURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directoryURL.path) {
                do {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                } catch {
                    fatalError("Failed to create override database directory: \(error)")
                }
            }
            return overrideURL
        }

        let appSupportURL: URL
        do {
            appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            fatalError("Failed to get Application Support directory: \(error)")
        }

        let imageBrowserDir = appSupportURL.appendingPathComponent("ImageBrowser", isDirectory: true)
        if !fileManager.fileExists(atPath: imageBrowserDir.path) {
            do {
                try fileManager.createDirectory(at: imageBrowserDir, withIntermediateDirectories: true)
            } catch {
                fatalError("Failed to create ImageBrowser directory: \(error)")
            }
        }

        return imageBrowserDir.appendingPathComponent("ImageBrowser.sqlite")
    }

    private static func removeDatabaseArtifacts(at dbURL: URL, fileManager: FileManager) {
        let urlsToRemove = [
            dbURL,
            URL(fileURLWithPath: dbURL.path + "-wal"),
            URL(fileURLWithPath: dbURL.path + "-shm")
        ]

        for url in urlsToRemove where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
    
    // MARK: - Migrations
    
    /// Database migrator that defines schema evolution
    public var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        #if DEBUG
        // Erase database on schema change for faster development iteration
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        
        // Migration v1: Create initial schema
        migrator.registerMigration("v1") { db in
            // Create image_metadata table
            try db.create(table: "image_metadata") { t in
                t.column("url", .text).primaryKey()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }

            // Create tags table
            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).unique().notNull()
            }

            // Create image_tags junction table
            try db.create(table: "image_tags") { t in
                t.column("url", .text).references("image_metadata", column: "url", onDelete: .cascade)
                t.column("tagId", .integer).references("tags", column: "id", onDelete: .cascade)
                t.primaryKey(["url", "tagId"])
            }

            // Create indexes for fast metadata queries
            try db.create(index: "rating", on: "image_metadata", columns: ["rating"])
            try db.create(index: "isFavorite", on: "image_metadata", columns: ["isFavorite"])
        }

        // Migration v1.1: Add tag index for fast case-insensitive lookups
        migrator.registerMigration("v1.1-tags") { db in
            // Create index on tags.name with COLLATE NOCASE for efficient autocomplete queries
            try db.create(index: "tags_on_name", on: "tags", columns: ["name"])
        }

        // Migration v1.1: Create smart_collections table
        migrator.registerMigration("v1.1-smart-collections") { db in
            // Create smart_collections table for saved filter rules
            try db.create(table: "smart_collections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("rules", .text).notNull()  // JSON storage for CollectionRules
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }

            // Create index on name for efficient collection lookups
            try db.create(index: "smart_collections_on_name", on: "smart_collections", columns: ["name"])
        }

        // Migration v1.1: Backfill matchAny key for legacy smart collection rules JSON
        migrator.registerMigration("v1.1-smart-collections-match-any-backfill") { db in
            try db.execute(sql: """
                UPDATE smart_collections
                SET rules = json_insert(CAST(rules AS TEXT), '$.matchAny', json('false'))
                WHERE json_valid(CAST(rules AS TEXT))
                  AND json_type(CAST(rules AS TEXT), '$.matchAny') IS NULL
                """)
        }

        migrator.registerMigration("v1.2-excluded-image-metadata") { db in
            try db.alter(table: "image_metadata") { table in
                table.add(column: "isExcluded", .boolean).notNull().defaults(to: false)
                table.add(column: "excludedAt", .datetime)
            }
        }

        return migrator
    }
}
