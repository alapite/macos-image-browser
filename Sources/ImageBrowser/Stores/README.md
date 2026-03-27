# Stores Architecture

ImageBrowser uses decomposed state management to prevent AppState bloat and enable independent state updates. This directory contains focused stores, each managing a specific aspect of application state.

## Overview

Instead of a monolithic `AppState` class with dozens of `@Published` properties, we split responsibilities into three focused stores:

- **ImageStore**: Image list and loading state management
- **FilterStore**: Filter criteria and active filters
- **ViewStore**: Navigation and slideshow state

This decomposition prevents cascade updates, improves testability, and makes state management more maintainable.

## Store Architecture

### ImageStore

**Purpose**: Manage image list and loading state with reactive database updates.

**Responsibilities**:
- Maintain list of `ImageFile` objects from filesystem
- Track loading state (`isLoadingImages`, `loadingProgress`)
- Track failed image loads (`failedImages`)
- Provide filtered images array (computed from FilterStore in Phase 10)
- Observe database changes via GRDB ValueObservation
- Update metadata (rating, favorite status) in database

**Key Properties** (max 10 @Published):
- `images: [ImageFile]` - List of images from filesystem
- `isLoadingImages: Bool` - Loading state indicator
- `failedImages: Set<URL>` - Failed image URLs
- `loadingProgress: Double` - Loading progress (0.0 to 1.0)
- `filteredImages: [ImageFile]` - Filtered images (Phase 10)

**Key Methods**:
- `updateRating(for:rating:)` - Update image rating in database
- `updateFavorite(for:isFavorite:)` - Update favorite status in database
- `startLoading()`, `updateProgress()`, `finishLoading()` - Loading state management
- `markFailed(_:)` - Mark image as failed to load

**Database Integration**:
- Uses GRDB `ValueObservation` to track database changes
- Auto-triggers UI updates when metadata is added/updated
- No manual UI refresh needed after database writes

**Example Usage**:
```swift
@StateObject var imageStore = ImageStore(dbPool: database.dbPool, filtering: filterStore)

// Access images
let images = imageStore.images

// Update rating (triggers automatic UI refresh)
try await imageStore.updateRating(for: imageUrl, rating: 5)
```

### FilterStore

**Purpose**: Manage filter criteria independently from image and view state.

**Responsibilities**:
- Track active filter criteria
- Provide computed property for filter active status
- Support filter reset to defaults
- Manage selected tags

**Key Properties** (max 10 @Published):
- `minimumRating: Int` - Minimum rating filter (0 = no filter)
- `showFavoritesOnly: Bool` - Show only favorited images
- `selectedTags: Set<String>` - Selected tags for filtering
- `dateRange: ClosedRange<Date>?` - Date range filter

**Key Computed Properties**:
- `isActive: Bool` - Returns true if any filter is set

**Key Methods**:
- `reset()` - Clear all filters to defaults
- `addTag(_:)`, `removeTag(_:)`, `toggleTag(_:)` - Tag management
- `isTagSelected(_:)` - Check if tag is selected
- `setDateRange(_:)`, `clearDateRange()` - Date range management

**Independence**:
- No dependencies on ImageStore or ViewStore
- Filter state changes don't trigger cascade updates
- Can be modified independently without affecting navigation

**Example Usage**:
```swift
@StateObject var filterStore = FilterStore()

// Apply filters
filterStore.minimumRating = 4
filterStore.showFavoritesOnly = true
filterStore.addTag("vacation")

// Check if any filter active
if filterStore.isActive {
    // Apply filtering logic
}

// Reset all filters
filterStore.reset()
```

### ViewStore

**Purpose**: Manage navigation and slideshow state independently from image loading.

**Responsibilities**:
- Track current image index for navigation
- Manage slideshow running state and interval
- Handle sort order preferences
- Provide navigation methods (next, previous)

**Key Properties** (max 10 @Published):
- `currentImageIndex: Int` - Current image index
- `isSlideshowRunning: Bool` - Slideshow running state
- `slideshowInterval: Double` - Slideshow interval in seconds
- `sortOrder: SortOrder` - Current sort order
- `customOrder: [String]` - Custom image order

**Key Enum**:
- `SortOrder: name, creationDate, custom` - Sort order options

**Key Methods**:
- `navigateToNext(totalImages:)` - Navigate to next image with wrap-around
- `navigateToPrevious(totalImages:)` - Navigate to previous image with wrap-around
- `navigateToIndex(_:totalImages:)` - Navigate to specific index
- `startSlideshow()`, `stopSlideshow()`, `toggleSlideshow()` - Slideshow control
- `updateSlideshowInterval(_:)` - Update slideshow interval
- `setSortOrder(_:)`, `cycleSortOrder()` - Sort order management
- `updateCustomOrder(_:)`, `clearCustomOrder()` - Custom order management
- `isIndexValid(totalImages:)` - Validate index
- `resetIndex()` - Reset to index 0

**Independence**:
- No dependencies on ImageStore or FilterStore
- Navigation state changes don't trigger cascade updates
- Can be modified independently without affecting filters

**Example Usage**:
```swift
@StateObject var viewStore = ViewStore()

// Navigate to next image
viewStore.navigateToNext(totalImages: images.count)

// Start slideshow
viewStore.startSlideshow()

// Change sort order
viewStore.sortOrder = .creationDate
```

## Design Principles

### 1. Max 10 @Published Properties per Store

Each store is limited to 10 `@Published` properties to prevent bloat:
- ImageStore: 5 properties
- FilterStore: 4 properties
- ViewStore: 5 properties

This ensures focused responsibilities and makes state easier to understand.

### 2. @MainActor Annotation for UI Thread Safety

All stores use `@MainActor` to ensure `@Published` property updates happen on the main thread (SwiftUI requirement). This prevents UI update crashes and race conditions.

```swift
@MainActor
final class ImageStore: ObservableObject {
    @Published var images: [ImageFile] = []
    // ...
}
```

### 3. Independent State (No Cascade Updates)

Stores communicate via direct references, not Combine between stores:
- FilterStore changes don't trigger ImageStore updates
- ViewStore changes don't trigger FilterStore updates
- Each store's `@Published` properties are independent

This prevents cascade updates that cause unnecessary re-renders.

### 4. ValueObservation for Reactive Database Updates

ImageStore uses GRDB's `ValueObservation` to automatically track database changes:
- When metadata is added/updated in the database
- ValueObservation triggers a publisher event
- ImageStore updates its `images` array
- SwiftUI re-renders automatically

No manual UI refresh needed after database writes.

### 5. Direct References Pattern

Stores communicate via direct references (not Combine):
- Views hold references to multiple stores
- Views can read from ImageStore, FilterStore, and ViewStore
- Stores don't subscribe to each other's changes

This prevents circular dependencies and makes testing easier.

## Usage in SwiftUI Views

```swift
struct ContentView: View {
    @StateObject var imageStore = ImageStore(dbPool: database.dbPool, filtering: filterStore)
    @StateObject var filterStore = FilterStore()
    @StateObject var viewStore = ViewStore()

    var body: some View {
        VStack {
            // Display images from ImageStore
            ImageListView(images: filteredImages)

            // Navigation controls using ViewStore
            HStack {
                Button("Previous") {
                    viewStore.navigateToPrevious(totalImages: imageStore.images.count)
                }
                Button("Next") {
                    viewStore.navigateToNext(totalImages: imageStore.images.count)
                }
            }

            // Filter controls using FilterStore
            FilterControls(minimumRating: $filterStore.minimumRating)
        }
    }

    // Computed property combining stores
    private var filteredImages: [ImageFile] {
        // Apply filters from FilterStore to images from ImageStore
        // (Implementation in Phase 10)
        imageStore.images
    }
}
```

## Migration Path from AppState

This is a gradual refactoring. The migration happens in phases:

### Phase 08-03 (Current Plan)
- ✅ Create ImageStore, FilterStore, ViewStore
- ✅ Implement basic functionality
- ✅ Add architecture documentation

### Phase 08-04 (Next Plan)
- Migrate AppState properties to stores
- Update ImageBrowserApp to inject stores as @EnvironmentObject
- Update ContentView to use stores instead of AppState
- Keep AppState for backward compatibility during transition

### Phase 09-10 (Future)
- Remove deprecated AppState properties
- Complete migration to store-based architecture
- Add advanced features using store pattern

## Benefits of Decomposed State

1. **Prevents Bloat**: Each store has max 10 @Published properties (vs. 20+ in monolithic AppState)
2. **Independent Updates**: Filter changes don't trigger navigation updates
3. **Better Testability**: Each store can be tested in isolation
4. **Clearer Responsibilities**: ImageStore vs. FilterStore vs. ViewStore
5. **Easier Maintenance**: Changes to filter logic don't affect navigation
6. **Scalability**: Easy to add new stores (e.g., SettingsStore, ExportStore)

## Testing

Each store can be tested independently:

```swift
// Test FilterStore
func testFilterStoreIsActive() {
    let store = FilterStore()
    XCTAssertFalse(store.isActive)

    store.minimumRating = 4
    XCTAssertTrue(store.isActive)

    store.reset()
    XCTAssertFalse(store.isActive)
}

// Test ViewStore navigation
func testViewStoreNavigation() {
    let store = ViewStore()
    let totalImages = 10

    store.navigateToNext(totalImages: totalImages)
    XCTAssertEqual(store.currentImageIndex, 1)

    store.navigateToPrevious(totalImages: totalImages)
    XCTAssertEqual(store.currentImageIndex, 0)
}
```

## References

- **RESEARCH.md**: Lines 247-289 (ValueObservation pattern)
- **RESEARCH.md**: Lines 506-525 (Filter store isolation)
- **RESEARCH.md**: Lines 527-551 (View-focused store separation)
- **AppState.swift**: Monolithic state being refactored (lines 5-193)
- **Phase 08-03 PLAN.md**: Implementation details and success criteria
