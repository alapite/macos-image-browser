# Roadmap: ImageBrowser Performance & Reliability

## Overview

Ship a fast, reliable macOS SwiftUI image browser experience on real-world folders by eliminating UI-blocking work (scan + decode), introducing caching where it matters, and adding automated tests to prevent performance and correctness regressions as we refactor.

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Baseline + Test Harness** - Establish safety rails (tests + structure) to refactor performance-critical code confidently.
- [ ] **Phase 2: Async Folder Scanning + Progress** - Make large-folder enumeration async, cancellable, and UI-friendly with progress feedback.
- [ ] **Phase 3: Thumbnail + Image Loading Pipeline** - Move decode off the render path and add caching to keep scrolling and navigation smooth.
- [ ] **Phase 4: Reliability for Navigation + Slideshow** - Harden state transitions, timer lifecycle, bounds, and persistence; expand regression coverage.
- [ ] **Phase 5: Polish + Performance Validation** - Tighten UX, verify memory/CPU behavior, and stabilize "fast on huge folders" as a baseline.

## Phase Details

### Phase 1: Baseline + Test Harness
**Goal**: Enable safe refactors by adding initial unit tests, small seams for injectability, and basic profiling/observability.
**Depends on**: Nothing (first phase)
**Research**: Unlikely (SwiftPM + unit testing patterns)
**Plans**: 3 plans

Plans:
- [ ] 01-01: Add SwiftPM test target and core unit tests for preferences + sorting + bounds
- [ ] 01-02: Introduce small seams in `AppState` for time/filesystem to make async + tests easier
- [ ] 01-03: Add lightweight instrumentation/logging points for scan duration + image load hotspots

### Phase 2: Async Folder Scanning + Progress
**Goal**: Folder scanning never blocks UI; scanning is cancellable; UI shows progress and handles partial results cleanly.
**Depends on**: Phase 1
**Research**: Likely (Swift concurrency cancellation patterns + FileManager enumeration behavior)
**Research topics**: Task cancellation patterns, structured concurrency for enumeration, best practice for progress reporting to SwiftUI (`@MainActor` updates)
**Plans**: 2 plans

Plans:
- [ ] 02-01: Implement async + cancellable scan pipeline in `AppState` (with cancellation on new folder selection)
- [ ] 02-02: Add progress + "scanning" UI state, plus failure tracking surfaced to the UI

### Phase 3: Thumbnail + Image Loading Pipeline
**Goal**: Thumbnails + main image loading avoid synchronous decoding in SwiftUI render; add caching and prefetch where useful.
**Depends on**: Phase 2
**Research**: Likely (image decoding/caching techniques on macOS)
**Research topics**: `CGImageSource` thumbnail generation, `NSCache` strategy, background decoding, memory tradeoffs, avoiding repeated `NSImage(contentsOf:)` during view updates
**Plans**: 3 plans

Plans:
- [ ] 03-01: Add thumbnail generation API and thumbnail cache keyed by file URL + size
- [ ] 03-02: Refactor main image load to background decode + cache; ensure UI updates on main thread
- [ ] 03-03: Prefetch neighbors (next/prev) and validate smooth scrolling in large lists

### Phase 4: Reliability for Navigation + Slideshow
**Goal**: Robust navigation + slideshow behavior with strong regression coverage and predictable lifecycle management.
**Depends on**: Phase 3
**Research**: Unlikely (internal state + timer lifecycle patterns)
**Plans**: 2 plans

Plans:
- [ ] 04-01: Harden slideshow start/stop/tick behavior; ensure timer invalidation + interval updates are correct
- [ ] 04-02: Expand unit tests around slideshow + navigation invariants and edge cases (empty folder, failures, rapid folder changes)

### Phase 5: Polish + Performance Validation
**Goal**: Validate performance on worst-case folders, reduce memory spikes, and polish user-facing feedback for long operations and failures.
**Depends on**: Phase 4
**Research**: Unlikely (measurement + UX polish)
**Plans**: 2 plans

Plans:
- [ ] 05-01: Soak test on large folders; tune cache sizes; confirm no UI jank during scan/scroll
- [ ] 05-02: Improve user-facing error/progress messaging and finalize "fast + reliable" baseline behaviors

## Progress

**Execution Order:**
Phases execute in numeric order (1 -> 2 -> 3 -> 4 -> 5)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Baseline + Test Harness | 0/3 | Not started | - |
| 2. Async Folder Scanning + Progress | 0/2 | Not started | - |
| 3. Thumbnail + Image Loading Pipeline | 0/3 | Not started | - |
| 4. Reliability for Navigation + Slideshow | 0/2 | Not started | - |
| 5. Polish + Performance Validation | 0/2 | Not started | - |
