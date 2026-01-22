# Coding Conventions

**Analysis Date:** 2026-01-21

## Naming Patterns

**Files:**
- Swift files use `UpperCamelCase.swift` matching the primary type/role (`AppState.swift`, `ContentView.swift`, `ImageBrowserApp.swift`).
- Build/config files use conventional names (`Package.swift`, `Info.plist`, `project.yml`, `build.sh`).

**Functions:**
- `lowerCamelCase` methods with imperative verbs for actions (e.g., `selectFolder()`, `navigateToNext()`, `toggleSlideshow()`) (`AppState.swift`).

**Variables:**
- `lowerCamelCase` for properties.
- Booleans commonly use `is...` prefix (e.g., `isSlideshowRunning`) (`AppState.swift`).

**Types:**
- `UpperCamelCase` for types (`AppState`, `ImageFile`, `Preferences`) (`AppState.swift`).
- Enums use `UpperCamelCase` with `lowerCamelCase` cases (`SortOrder.name`, `.creationDate`, `.custom`) (`AppState.swift`).

## Code Style

**Formatting:**
- Indentation: 4 spaces (`ContentView.swift`, `AppState.swift`, `Package.swift`).
- Braces: opening brace on the same line (`ImageBrowserApp.swift`, `AppState.swift`).
- Long SwiftUI modifier chains are typically wrapped across lines for readability (`ContentView.swift`).
- Trailing commas in multi-line argument lists/collection literals: mixed; `AGENTS.md` recommends them.

**Linting:**
- Not detected (no `.swiftlint.yml`).

## Import Organization

**Order (observed):**
- SwiftUI views primarily `import SwiftUI` (`ImageBrowserApp.swift`, `ContentView.swift`).
- Non-UI files import Foundation + other frameworks as needed (e.g., `import Foundation`, `import Combine`, `import AppKit`) (`AppState.swift`).
- One module per line.

## Error Handling

**Patterns:**
- Best-effort decoding/encoding using `try?` for preferences persistence (`AppState.swift`).
- Image decode failures are tracked in a `failedImages` set used by the UI (`AppState.swift`, `ContentView.swift`).
- Limited user-facing error messaging; failures are often silent.

## Logging

**Framework:**
- Not detected (no `os.Logger` usage in app sources).

**Patterns:**
- No consistent logging strategy observed.

## Comments

**When to Comment:**
- Comments are sparse and generally section-level.
- `// MARK: - ...` is used to separate sections (e.g., persistence) (`AppState.swift`).

## Function Design

**Size:**
- Larger view file with multiple subviews colocated (`ContentView.swift`).
- App state methods group related behaviors (loading, sorting, slideshow, persistence) (`AppState.swift`).

## Module Design

**Organization pattern:**
- Flat layout with most view types defined inside `ContentView.swift`.
- Models live inside `AppState.swift`.

---

*Convention analysis: 2026-01-21*
*Update when patterns change*
