# Database Module

This module provides GRDB-based SQLite persistence for image metadata.

## Schema

### Tables

#### `image_metadata`

Stores metadata for individual images.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| url | TEXT | PRIMARY KEY | File path as standardized URL string |
| rating | INTEGER | NOT NULL DEFAULT 0 | Rating from 0-5 stars (0 = unrated) |
| isFavorite | BOOLEAN | NOT NULL DEFAULT FALSE | Favorite flag |
| createdAt | DATE | NOT NULL | First created timestamp |
| updatedAt | DATE | NOT NULL | Last modified timestamp |

**Indexes:**
- `rating` index on `rating` column for fast rating-based queries
- `isFavorite` index on `isFavorite` column for fast favorite filtering

These indexes ensure sub-10ms query performance on 10K+ images.

#### `tags`

Stores user-defined tags for organizing images.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | AUTOINCREMENT PRIMARY KEY | Unique tag identifier |
| name | TEXT | UNIQUE NOT NULL | Tag name |

#### `image_tags`

Junction table for many-to-many relationship between images and tags.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| url | TEXT | REFERENCES image_metadata(url) ON DELETE CASCADE | Image file URL |
| tagId | INTEGER | REFERENCES tags(id) ON DELETE CASCADE | Tag identifier |

**Primary Key:** (url, tagId)

## Usage

### Accessing the Database

The database is constructed at the composition root and passed where needed:

```swift
import GRDB

let database = AppDatabase(
    configuration: AppDatabaseConfiguration.from(environment: ProcessInfo.processInfo.environment)
)
let dbPool = database.dbPool
```

### Example Queries

#### Fetch metadata by URL

```swift
let metadata = try await dbPool.read { db in
    try ImageMetadataRecord.fetchOne(db, key: "/path/to/image.jpg")
}
```

#### Fetch all favorites

```swift
let favorites = try await dbPool.read { db in
    try ImageMetadataRecord
        .filter(Column("isFavorite") == true)
        .fetchAll(db)
}
```

#### Fetch images by rating

```swift
let fiveStarImages = try await dbPool.read { db in
    try ImageMetadataRecord
        .filter(Column("rating") == 5)
        .fetchAll(db)
}
```

#### Save or update metadata

```swift
var metadata = ImageMetadataRecord(
    url: "/path/to/image.jpg",
    rating: 5,
    isFavorite: true
)
try await dbPool.write { db in
    try metadata.insert(db)
}
```

#### Update rating

```swift
try await dbPool.write { db in
    try ImageMetadataRecord
        .filter(key: "/path/to/image.jpg")
        .updateAll(db, Column("rating").set(to: 4))
}
```

## Migration Strategy

Database migrations are defined in `AppDatabase.migrator` and run automatically on app startup.

### Development Mode

In DEBUG builds, `eraseDatabaseOnSchemaChange` is enabled. This means the database is automatically recreated when the schema changes, allowing faster iteration during development.

**Note:** This will delete all existing metadata when the schema changes. Use with caution.

### Production Mode

In RELEASE builds, schema changes must be handled via explicit migrations. New migrations should:

1. Be added to `AppDatabase.migrator`
2. Be named incrementally (e.g., "v2", "v3")
3. Handle both new installs and upgrades from previous versions

Example:

```swift
migrator.registerMigration("v2") { db in
    // Add new column
    try db.alter(table: "image_metadata") { t in
        t.add(column: "newField", .text).defaults(to: "")
    }
}
```

## WAL Mode

The database runs in **WAL (Write-Ahead Logging)** mode for better concurrency:

- **Multiple readers can access the database simultaneously** without blocking each other
- **Readers don't block writers** - UI remains responsive during metadata writes
- **Writers don't block readers** - background updates don't freeze the UI

This is critical for a smooth user experience when working with large photo libraries.

## Database Location

The SQLite database file is stored at:

```
~/Library/Application Support/ImageBrowser/ImageBrowser.sqlite
```

WAL files (`ImageBrowser.sqlite-wal`, `ImageBrowser.sqlite-shm`) are also present in the same directory.

## Performance Considerations

### Indexes

Indexes on `rating` and `isFavorite` ensure fast filtering and sorting operations. When adding new queries that filter on specific columns, consider adding indexes if:

1. The query is performance-critical (user-facing)
2. The column has high cardinality (many distinct values)
3. The table will contain 10K+ rows

### Concurrent Access

Always use `DatabasePool` (not `DatabaseQueue`) for non-blocking reads. `AppDatabase` provides this out of the box once constructed by the app container.

### Bulk Operations

For bulk inserts or updates, use transactions:

```swift
try await dbPool.write { db in
    try db.inTransaction {
        for metadata in metadataList {
            try metadata.insert(db)
        }
        return .commit
    }
}
```

## Future Phases

This database schema supports all planned v1.1 features:

- **Phase 9:** Favorites & Ratings (core table + indexes already in place)
- **Phase 10:** Filtering System (indexes enable fast multi-criteria filtering)
- **Phase 11:** Smart Collections & Tags (tags and image_tags tables ready)
