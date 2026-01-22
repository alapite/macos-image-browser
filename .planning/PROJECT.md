# ImageBrowser Performance & Reliability

## What This Is

A macOS SwiftUI image browser that lets you pick a folder and browse images quickly with a sidebar list, thumbnails, and an optional slideshow. This project is focused on making the existing app feel fast and reliable on real-world folders while keeping the codebase small and dependency-free.

## Core Value

Browsing a folder of images should feel instant: no UI freezes, smooth scrolling, and predictable navigation.

## Requirements

### Validated

- ✓ Browse local image folders (select folder, enumerate image files, display images) — existing (`AppState.swift`, `ContentView.swift`)
- ✓ Basic navigation + slideshow (next/prev, timer-driven playback) — existing (`AppState.swift`, `ContentView.swift`)
- ✓ Preferences persistence via `UserDefaults` (interval/sort/custom order/last folder) — existing (`AppState.swift`)

### Active

- [ ] Scanning large folders is async + cancellable and never blocks the UI (with progress feedback) (`AppState.swift`, `ContentView.swift`)
- [ ] Thumbnails and main image loading use caching and avoid synchronous decode during SwiftUI render (`ContentView.swift`)
- [ ] Add good automated test coverage for core logic:
  - `AppState` sorting + navigation bounds + preferences encode/decode (`AppState.swift`)
  - Folder scanning behavior (fixtures via temp dirs; extension filtering; failure tracking) (`AppState.swift`)
  - Slideshow start/stop/tick + interval update behavior (`AppState.swift`)

### Out of Scope

- Tagging/ratings/search — explicitly excluded for v1 to avoid turning this into a photo library manager
- Cloud sync / accounts — excluded to keep it local-only and simple
- Photo editing tools — excluded; viewer-only

## Context

- Codebase is a small SwiftUI macOS app with a centralized `ObservableObject` state container (`AppState.swift`) injected via `.environmentObject` (`ImageBrowserApp.swift`).
- Current implementation loads `NSImage(contentsOf:)` directly inside view rendering for both the main viewer and thumbnails (`ContentView.swift`), which risks stutter and high memory usage.
- Folder scanning and file attribute lookup happen synchronously (`AppState.swift`), which can freeze the UI on large or deep folders.
- Project uses Apple frameworks only (SwiftUI/Combine/Foundation/AppKit) and has no external SwiftPM dependencies (`Package.swift`).

## Constraints

- **Tech stack**: Must stay macOS + SwiftUI — keep the existing platform and architecture.
- **Dependencies**: No new dependencies — prefer Apple frameworks only (avoid adding third-party SPM packages).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Prioritize performance on large folders (scan + decode + caching) | This is the primary pain point; it drives perceived quality | — Pending |
| Add strong unit coverage around `AppState` + scanning + slideshow | Prevent regressions while refactoring for async and caching | — Pending |
| Keep v1 viewer-focused (no tagging/ratings/search) | Scope control; avoid building a library manager | — Pending |
| No new dependencies | Keep the project lightweight and easier to maintain | — Pending |

---
*Last updated: 2026-01-21 after initialization*
