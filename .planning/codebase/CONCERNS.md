# Codebase Concerns

**Analysis Date:** 2026-01-21

## Tech Debt

**Monolithic view file:**
- Issue: `ContentView.swift` contains the root layout plus multiple substantial subviews (sidebar, viewer, settings, custom order editor).
- Why: Simple early-stage structure; easiest way to iterate.
- Impact: Harder to optimize image loading, fix state flows, or add tests without regressions.
- Fix approach: Split subviews into dedicated files and isolate image-loading/caching into a service.

**AppState owns many responsibilities:**
- Issue: `AppState.swift` mixes state, persistence, file picking, folder scanning, sorting, and slideshow timer logic.
- Impact: Harder to test and harder to make performance changes safely.
- Fix approach: Extract focused helpers (e.g., `ImageScanner`, `ImageCache`, `PreferencesStore`) and keep `AppState` as coordinator.

## Known Bugs

**Settings changes may not apply/persist consistently:**
- Symptoms: Sort order and slideshow interval may not take effect immediately or persist after relaunch.
- Trigger: Settings UI binds directly to `@Published` properties in `ContentView.swift` instead of calling intent methods.
- Root cause: Side-effectful logic exists in `AppState` methods (e.g., re-sort, restart timer, persist), but UI bypasses them.
- Fix approach: Bind via explicit setters (e.g., call `AppState.updateSlideshowInterval(_:)` / `AppState.setSortOrder(_:)`) from `ContentView.swift`.

**Custom order breaks with duplicate filenames across folders:**
- Symptoms: Unexpected ordering when two images share the same name in different subfolders.
- Trigger: Custom order uses filename strings as identifiers (`AppState.swift`) and editor lists names only (`ContentView.swift`).
- Fix approach: Store ordering by stable IDs like file URL paths instead of names.

## Security Considerations

**Sandbox compatibility (security-scoped bookmarks):**
- Risk: Persisting `lastFolder` as a plain path string may fail after relaunch under sandboxing.
- Current behavior: `AppState.swift` stores and reloads folder via `.path`.
- Recommendations: Use security-scoped bookmarks for persisted folder access if sandboxing/distribution is a goal.

**Large/untrusted folder traversal:**
- Risk: Recursive enumeration can hang the app on huge directory trees or problematic filesystem layouts.
- Location: Folder scanning via `FileManager` enumerator in `AppState.swift`.
- Recommendations: Consider skipping packages, controlling recursion, detecting symlinks/loops, and surfacing progress.

## Performance Bottlenecks

**Synchronous image decoding in SwiftUI `body`:**
- Problem: Views call `NSImage(contentsOf:)` directly during render for full images and thumbnails.
- Locations: `ContentView.swift` (main viewer and thumbnail view).
- Cause: Disk I/O + decode can happen repeatedly due to view updates.
- Improvement path: Add async image loading, thumbnail generation (e.g., via ImageIO), and caching (`NSCache`).

**Folder scanning runs on main thread:**
- Problem: Enumerating folders and reading file attributes can block UI.
- Location: `AppState.swift`.
- Improvement path: Move scanning/sorting to a background task, publish results on the main actor.

**Custom sort is O(n^2) for large libraries:**
- Problem: Sorting uses repeated `firstIndex(of:)` lookups.
- Location: `AppState.swift`.
- Improvement path: Precompute an index map `[String: Int]` (or `[URL: Int]`) before sorting.

## Fragile Areas

**Silent failures during scan/persistence:**
- Why fragile: Some failures are ignored (`FileManager.enumerator(...) == nil`, `try?` preferences encode/decode).
- Locations: `AppState.swift`.
- Safe modification: Add explicit error states or logging before changing scan/persistence behavior.
- Test coverage: None.

**Unstable identity for list items:**
- Why fragile: `ImageFile` uses random UUIDs per load; list diffing/selection stability may degrade across reloads.
- Locations: `AppState.swift`, `ContentView.swift`.
- Fix approach: Use a stable identifier (e.g., file URL) for `Identifiable`.

## Dependencies at Risk

**Build script installs tooling:**
- Risk: `build.sh` installs Homebrew packages (XcodeGen) which is a side effect in local/CI contexts.
- Location: `build.sh`.
- Migration plan: Document prerequisites and/or provide an opt-in install step.

## Missing Critical Features

**Progress feedback for long scans:**
- Problem: Large folders appear to freeze the UI during scan.
- Locations: `AppState.swift`, `ContentView.swift`.
- Implementation complexity: Medium (async scan + progress reporting).

## Test Coverage Gaps

**No automated tests:**
- What's not tested: Sorting, preference persistence, slideshow behavior.
- Locations: `Package.swift` (no test target), no `Tests/` directory.
- Priority: Medium (small app, but core behaviors are stateful and regression-prone).

---

*Concerns audit: 2026-01-21*
*Update as issues are fixed or new ones discovered*
