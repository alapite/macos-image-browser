---
phase: 01-baseline-test-harness
plan: 02
subsystem: testing
tags: [swift, xctest, userdefaults, filemanager]

# Dependency graph
requires:
  - phase: 01-baseline-test-harness
    provides: Baseline XCTest harness and unit test conventions
provides:
  - Injectable seams in AppState for preferences persistence and filesystem enumeration
  - Deterministic scan behavior tests (extension filtering + failedImages tracking)
affects: [02-async-folder-scanning-progress, 04-reliability-navigation-slideshow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AppState dependencies are injected via small protocols with production defaults"
    - "Tests use isolated UserDefaults suites, never UserDefaults.standard"

key-files:
  created:
    - Tests/ImageBrowserTests/ScanningTests.swift
  modified:
    - AppState.swift
    - Tests/ImageBrowserTests/AppStateTests.swift
    - Tests/ImageBrowserTests/PreferencesTests.swift
    - Tests/ImageBrowserTests/TestSupport.swift

key-decisions:
  - "Model seams as minimal protocols (PreferencesStore, FileSystem) with default implementations"
  - "Make scanning tests deterministic via a fake FileSystem (no temp dirs needed)"

patterns-established:
  - "AppState init accepts dependencies but keeps behavior identical via defaults"
  - "TestSupport exposes makeIsolatedUserDefaults() helper for suite-scoped isolation"

issues-created: []

# Metrics
duration: 6 min
completed: 2026-01-22
---

# Phase 1 Plan 02: Injectable Seams for Scanning + Preferences Summary

**AppState can now be tested deterministically by injecting persistence and filesystem dependencies, unlocking safe async-scanning refactors next.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-01-22T10:23:14Z
- **Completed:** 2026-01-22T10:30:13Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added a minimal `PreferencesStore` seam and routed Preferences load/save through it (default: UserDefaults)
- Added a minimal `FileSystem` seam and routed folder enumeration + creation-date reads through it (default: FileManager)
- Added scan-focused tests that validate extension filtering and `failedImages` behavior without touching real disk or global preferences

## Task Commits

Each task was committed atomically:

1. **Task 1: Add injectable seams for preferences + filesystem enumeration (keep behavior identical)** - `4ce45ee` (refactor)
2. **Task 2: Expand tests to cover scanning behavior using temp dirs or fakes** - `75eaf9f` (test)

## Files Created/Modified

- `AppState.swift` - Adds `PreferencesStore` + `FileSystem` abstractions and injects them into persistence + scanning
- `Tests/ImageBrowserTests/ScanningTests.swift` - Deterministic scan behavior tests (filtering + failures)
- `Tests/ImageBrowserTests/AppStateTests.swift` - Uses suite-scoped UserDefaults via injected store
- `Tests/ImageBrowserTests/PreferencesTests.swift` - Adds round-trip test for UserDefaults-backed store
- `Tests/ImageBrowserTests/TestSupport.swift` - Adds `makeIsolatedUserDefaults()` helper

## Decisions Made

- Used protocol-based seams (`PreferencesStore`, `FileSystem`) with production default implementations to keep the refactor small and reversible.
- Used a fake filesystem in tests (instead of temp dirs) to make failure scenarios easy to model and keep tests fast.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness

- Ready for `01-03-PLAN.md` (add lightweight logging/instrumentation).
- Async scanning work can now be done behind `FileSystem` with deterministic test coverage.

---
*Phase: 01-baseline-test-harness*
*Completed: 2026-01-22*
