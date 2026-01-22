# Architecture

**Analysis Date:** 2026-01-21

## Pattern Overview

**Overall:** Single-process SwiftUI macOS application with a shared `ObservableObject` state container.

**Key Characteristics:**
- One window scene with the entire UI driven from shared state (`ImageBrowserApp.swift`, `ContentView.swift`)
- Centralized state + side effects (filesystem enumeration, `NSOpenPanel`, slideshow `Timer`) live in `AppState` (`AppState.swift`)
- Local-only: loads images from disk, persists preferences in `UserDefaults` (`AppState.swift`)

## Layers

**UI Layer:**
- Purpose: Render the app and invoke intent-like actions.
- Contains: SwiftUI views and view-local UI state.
- Depends on: `AppState` via `@EnvironmentObject`.
- Location: `ContentView.swift` (includes `ContentView`, `SidebarView`, `MainImageViewer`, `SettingsView`, etc.).

**State / ViewModel Layer:**
- Purpose: Single source of truth for app state + all mutations.
- Contains: `ObservableObject` state, navigation, sorting, persistence, slideshow timer.
- Depends on: Foundation + AppKit (`NSOpenPanel`).
- Location: `AppState.swift`.

**Model Layer:**
- Purpose: Lightweight value types representing app data.
- Contains: `ImageFile`, `Preferences`, `SortOrder`.
- Location: `AppState.swift`.

## Data Flow

**Folder Selection + Image Load:**

1. User clicks "Select Folder" in the UI (`ContentView.swift`).
2. `AppState.selectFolder()` opens `NSOpenPanel` and sets `selectedFolder` (`AppState.swift`).
3. `AppState.loadImages(from:)` enumerates the folder, filters by image extensions, and builds `[ImageFile]` (`AppState.swift`).
4. `AppState.sortImages(...)` sorts based on current `sortOrder` (`AppState.swift`).
5. `@Published` changes (`images`, `currentImageIndex`, etc.) trigger SwiftUI updates (`ContentView.swift`).
6. Views load images from disk using `NSImage(contentsOf:)` (main viewer + thumbnails) (`ContentView.swift`).

**State Management:**
- In-memory state stored in `AppState` (`@Published` properties) (`AppState.swift`).
- Preferences persisted to `UserDefaults` as JSON (`AppState.swift`).
- Slideshow uses an in-memory `Timer` (`AppState.swift`).

## Key Abstractions

**AppState:**
- Purpose: Source of truth + intent API for the UI.
- Examples: `selectFolder()`, `navigateToNext()`, `toggleSlideshow()`, `setSortOrder(_:)`.
- Location: `AppState.swift`.

**ImageFile:**
- Purpose: Minimal metadata needed by UI.
- Fields: `url`, `name`, `creationDate`.
- Location: `AppState.swift`.

**Preferences:**
- Purpose: Persisted user preferences and last folder.
- Stored as JSON in `UserDefaults` under `ImageBrowserPreferences`.
- Location: `AppState.swift`.

## Entry Points

**App Entry:**
- Location: `ImageBrowserApp.swift`
- Triggers: Launching the macOS app
- Responsibilities: Create `AppState` and inject it with `.environmentObject`, show `ContentView`.

**Build Entry (SwiftPM):**
- Location: `Package.swift`
- Triggers: `swift build`, `swift run ImageBrowser`
- Responsibilities: Defines executable target and sources.

## Error Handling

**Strategy:** Best-effort / largely silent failures.

**Patterns:**
- `try?` used for preferences encode/decode (`AppState.swift`).
- Some failures tracked as `failedImages` (used to show UI warning indicators) (`AppState.swift`, `ContentView.swift`).

## Cross-Cutting Concerns

**Persistence:**
- Preferences stored in `UserDefaults` (`AppState.swift`).

**Permissions:**
- Folder access usage strings declared in `Info.plist`.

**Build / Packaging:**
- XcodeGen + xcodebuild path for producing a signed `.app` bundle (`build.sh`, `project.yml`).

---

*Architecture analysis: 2026-01-21*
*Update when major patterns change*
