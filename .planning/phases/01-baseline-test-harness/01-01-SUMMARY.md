---
phase: 01-baseline-test-harness
plan: 01
subsystem: testing
tags: [swiftpm, xctest, swift]

# Dependency graph
requires: []
provides:
  - SwiftPM test target (`ImageBrowserTests`) wired into the package
  - Initial unit tests covering AppState sorting + navigation bounds
  - Preferences Codable regression coverage
affects: [01-baseline-test-harness, 02-async-folder-scanning-progress, 04-reliability-navigation-slideshow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SwiftPM tests live in Tests/ImageBrowserTests and use XCTest (@testable import)"

key-files:
  created:
    - Tests/ImageBrowserTests/TestSupport.swift
    - Tests/ImageBrowserTests/AppStateTests.swift
    - Tests/ImageBrowserTests/PreferencesTests.swift
  modified:
    - Package.swift

key-decisions:
  - "Keep tests pure/unit-level by constructing ImageFile values directly (no filesystem I/O)"
  - "Exclude Tests/ and .planning/ from the executable target to avoid SwiftPM source warnings"

patterns-established:
  - "TestSupport.swift provides deterministic helpers (makeDate, makeImageFile) shared by tests"

issues-created: []

# Metrics
duration: 5 min
completed: 2026-01-22
---

# Phase 1 Plan 01: Baseline Test Harness Summary

**SwiftPM now runs a small XCTest suite that locks in core AppState invariants and Preferences encoding behavior.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-01-22T10:12:05Z
- **Completed:** 2026-01-22T10:17:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added an `ImageBrowserTests` SwiftPM test target and test module skeleton
- Added unit tests for AppState sorting + navigation wrap/bounds behavior
- Added unit tests for Preferences JSON round-trip and safe decoding when `lastFolder` is missing

## Task Commits

Each task was committed atomically:

1. **Task 1: Add SwiftPM test target + test directory skeleton** - `7af6054` (test)
2. **Task 2: Add core AppState unit tests (sorting + navigation + preferences encoding)** - `bcf059b` (test)

## Files Created/Modified

- `Package.swift` - Adds `ImageBrowserTests` and tightens excludes so SwiftPM doesn’t treat non-source files as part of the executable target
- `Tests/ImageBrowserTests/TestSupport.swift` - Deterministic date + ImageFile constructors for tests
- `Tests/ImageBrowserTests/AppStateTests.swift` - Sorting + navigation invariant coverage
- `Tests/ImageBrowserTests/PreferencesTests.swift` - Codable regression coverage for Preferences

## Decisions Made

- Keep tests unit-level (construct `ImageFile` arrays directly) so they run fast and don’t depend on local filesystem contents.
- Exclude `Tests/` and `.planning/` from the executable target to prevent SwiftPM from warning about “unhandled” files.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness

- `swift test` passes with meaningful coverage, ready for `01-02-PLAN.md` (injectability seams).

---
*Phase: 01-baseline-test-harness*
*Completed: 2026-01-22*
