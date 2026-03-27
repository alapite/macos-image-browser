# ImageBrowser Models

This directory contains data models for the ImageBrowser application.

## ImageFile

### Purpose

`ImageFile` represents an image file in the filesystem with optional metadata. It provides value semantics and thread safety for image file representation throughout the application.

### Properties

```swift
struct ImageFile: Identifiable, Equatable, Sendable {
    let url: URL              // File system URL
    let name: String          // Display name (filename with extension)
    let creationDate: Date    // File creation date from filesystem
    var metadata: ImageMetadata?  // Optional metadata (lazy loaded)
}
```

### Computed Properties

The model provides safe access to metadata fields with sensible defaults:

```swift
var rating: Int         // Returns metadata?.rating ?? 0
var isFavorite: Bool    // Returns metadata?.isFavorite ?? false
```

This design allows UI code to access `image.rating` without optional unwrapping, while new code can explicitly check `image.metadata` when needed.

### Lazy Loading Pattern

The optional `metadata` property enables lazy loading - metadata is fetched from the database only when needed, preventing expensive eager loading at startup.

**Benefits:**
- Fast app startup - no blocking database queries
- UI displays images immediately without waiting for metadata
- Metadata can be fetched asynchronously in the background
- Memory efficient - only loads metadata for viewed images

**Usage pattern:**
```swift
// UI code - works even when metadata is nil
Text("Rating: \(image.rating)")  // Displays "Rating: 0" if not loaded

// Metadata loading code (Phase 08-03)
if image.metadata == nil {
    image.metadata = await metadataStore.load(for: image.id)
}
```

### Value Semantics (Struct vs Class)

`ImageFile` is a `struct` (value type), not a `class` (reference type), for several reasons:

**Thread Safety:**
- Value types are inherently thread-safe when passed around
- No shared mutable state between actors
- Each copy is independent - no race conditions from concurrent access

**Immutability:**
- Core properties (`url`, `name`, `creationDate`) are immutable (`let`)
- Only `metadata` can be modified (for lazy loading)
- Prevents accidental mutations in UI code

**Performance:**
- No reference counting overhead
- Better cache locality
- Copy-on-write for arrays of images

**Equality:**
- Two `ImageFile` instances are equal if they point to the same file URL
- Useful for identifying duplicate references in collections

## ImageMetadata

### Purpose

`ImageMetadata` stores user-generated metadata in memory for quick access without database queries. This lightweight struct is used in `ImageFile` for lazy loading pattern.

### Properties

```swift
struct ImageMetadata: Sendable {
    var rating: Int         // 0-5 star rating
    var isFavorite: Bool    // Favorite flag for quick access
}
```

### Relationship to ImageMetadataRecord

`ImageMetadata` is the in-memory representation. For database persistence, see `ImageMetadataRecord` in the Database module:

- **ImageMetadata** (this file): Lightweight in-memory struct for use in ImageFile
- **ImageMetadataRecord** (Database module): GRDB record with timestamps for persistence

When loading from database, convert: `ImageMetadata(record.rating, record.isFavorite)`
When saving to database, convert: `ImageMetadataRecord(url, metadata.rating, metadata.isFavorite)`

### Future Extensions

Later phases will add additional metadata fields:
- **Phase 09:** Tags and collections
- **Phase 11:** Smart collections based on metadata queries
- **Phase 13:** EXIF data extraction (camera settings, location, etc.)

## Usage Examples

### Displaying Images (UI Code)

```swift
// SwiftUI view - works with or without metadata loaded
struct ImageRow: View {
    let image: ImageFile

    var body: some View {
        HStack {
            Text(image.name)
            Spacer()
            if image.isFavorite {
                Image(systemName: "star.fill")
            }
            Text("★\(image.rating)")
        }
    }
}
```

### Loading Metadata (Background Task)

```swift
// In ImageStore (Phase 08-03)
for image in images {
    if image.metadata == nil {
        image.metadata = await metadataStore.load(for: image.id)
    }
}
```

### Filtering by Metadata

```swift
// In FilterStore (Phase 10)
let favorites = images.filter { $0.isFavorite }
let highlyRated = images.filter { $0.rating >= 4 }
```

## Future Models

As the application grows, additional models will be added to this directory:

**Planned for Phase 11:**
- `Tag`: User-defined tags for image organization
- `SmartCollection`: Dynamic collections based on metadata queries

**Planned for Phase 13:**
- `EXIFMetadata`: Camera settings, GPS location, timestamp
- `ImageFormat`: Enum representing supported image formats

## Design Principles

1. **Value Types:** Use structs for thread safety and immutability
2. **Lazy Loading:** Optional metadata prevents eager loading
3. **Safe Defaults:** Computed properties provide non-optional access
4. **Backward Compatibility:** Existing code continues to work without changes
5. **Codable:** All models support serialization for persistence

## Related Files

- `Sources/ImageBrowser/AppState.swift` - Main application state (uses ImageFile)
- `Sources/ImageBrowser/Stores/` - Data stores for metadata persistence (Phase 08-03)
- `.planning/phases/08-metadata-infrastructure/` - Phase 8 planning documents
