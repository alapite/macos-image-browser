---
phase: 01-baseline-test-harness
plan: 03
subsystem: [testing]
tags: [oslog, oslogger, signpost, swiftui, nsimage]

# Dependency graph
requires:
  - phase: 01-baseline-test-harness
    provides: injectable seams for filesystem/preferences
provides:
  - Coarse scan duration + counts logs for folder enumeration
  - Coarse image decode timing/failure logs for main image + thumbnails
  - Optional signpost interval for scan visualization in Instruments
affects: [phase-02-async-scan, phase-03-image-pipeline, performance]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Centralized os.Logger categories in Logging.swift", "Coarse/sampled logging to avoid spam"]

key-files:
  created: [Logging.swift]
  modified: [AppState.swift, ContentView.swift, Package.swift]

key-decisions:
  - "Use os.Logger + optional OSSignposter for scan/image observability without adding dependencies"
  - "Sample image decode logs (thumbnails especially) to avoid per-frame/per-cell noise"

patterns-established:
  - "Logging: define Logger categories via Logger extension with shared subsystem"
  - "Performance measurement: use DispatchTime for elapsedMs and keep logs coarse"

issues-created: []

# Metrics
duration: 7 min
completed: 2026-01-22
---

# Phase 1 Plan 3: Baseline Instrumentation Summary

**Added dependency-free os.Logger + signpost instrumentation for folder scans and image decode hotspots to make performance regressions visible in Console/Instruments.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-01-22T10:32:12Z
- **Completed:** 2026-01-22T10:39:22Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Folder scanning logs a single coarse entry per scan with counts + elapsed time
- Scan path optionally emits a signpost interval for Instruments visualization
- Main image and thumbnail decode paths log coarse timing and failures (sampled)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add scan instrumentation (duration + counts) in AppState** - `4431818` (feat)
2. **Task 2: Add image load instrumentation (decode time + failures) in the SwiftUI layer** - `edb7435` (feat)

## Files Created/Modified
- `Logging.swift` - Centralizes `os.Logger` categories + scan signposter
- `AppState.swift` - Emits scan timing/count logs + optional signpost interval
- `ContentView.swift` - Wraps `NSImage(contentsOf:)` with sampled timing/failure logs
- `Package.swift` - Adds `Logging.swift` to SwiftPM executable sources

## Decisions Made
- Use `os.Logger` for structured logs and `OSSignposter` for scan intervals (macOS 12+) so regressions can be inspected in Console/Instruments without new dependencies.
- Keep logs coarse and sampled to avoid spamming output during large-folder loads and thumbnail list renders.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Phase 1 complete; ready for `02-01-PLAN.md` (async + cancellable scan pipeline).

---
*Phase: 01-baseline-test-harness*
*Completed: 2026-01-22*
