# Agent Instructions (macos-image-browser)

This repo is a small SwiftUI macOS app. It can be built via Swift Package Manager (SPM) for fast iteration, or via `build.sh` which generates an Xcode project using XcodeGen and produces a signed `.app` bundle.

Cursor/Copilot rules:
- No `.cursorrules`, no `.cursor/rules/`, and no `.github/copilot-instructions.md` were found at time of writing.

## Quick Commands

Prereqs:
- macOS 13+
- Xcode installed (provides SDKs + `xcodebuild`)
- Homebrew recommended (used to install XcodeGen in `build.sh`)

SPM (fast local build/run):
- Build: `swift build`
- Run (CLI executable): `swift run ImageBrowser`
- Clean build artifacts: `rm -rf .build`
- Package metadata: `swift package dump-package`

XcodeGen + Xcode build (produces `.app`):
- Build app bundle: `./build.sh`
- Run app bundle: `open ImageBrowser.app`
- Regenerate Xcode project: `xcodegen generate`

Direct `xcodebuild` (if `ImageBrowser.xcodeproj` exists):
- Build: `xcodebuild -project ImageBrowser.xcodeproj -scheme ImageBrowser -configuration Release -destination "platform=macOS" build`

## Tests

Current status:
- No `Tests/` target exists; `swift test` reports "no tests found".

If/when tests are added (SwiftPM conventions):
- Run all tests: `swift test`
- List tests: `swift test list`
- Run a single test (preferred):
  - `swift test --filter "<TestModule>.<TestCase>/<testMethod>"`
  - Example: `swift test --filter "ImageBrowserTests.AppStateTests/testSortByName"`
- Run all tests in a test case:
  - `swift test --filter "<TestModule>.<TestCase>"`
  - Example: `swift test --filter "ImageBrowserTests.AppStateTests"`

Xcode test equivalents (once the scheme contains a test bundle):
- All tests: `xcodebuild test -project ImageBrowser.xcodeproj -scheme ImageBrowser -destination "platform=macOS"`
- Single test: `xcodebuild test -project ImageBrowser.xcodeproj -scheme ImageBrowser -destination "platform=macOS" -only-testing:<TestBundle>/<TestClass>/<testMethod>`

## Lint / Formatting

Current status:
- No SwiftLint/SwiftFormat config found in the repo.

Recommended local tooling (optional; do not assume CI runs it):
- SwiftFormat: `brew install swiftformat` then `swiftformat .`
- SwiftLint: `brew install swiftlint` then `swiftlint`

If you introduce one of these tools, also add the config file (e.g. `.swiftformat` / `.swiftlint.yml`) and document new commands here.

## Project Layout

- `ImageBrowserApp.swift`: SwiftUI `@main` entrypoint.
- `ContentView.swift`: Root view + subviews.
- `AppState.swift`: Shared state (`ObservableObject`), persistence, and file enumeration.
- `project.yml`: XcodeGen spec.
- `build.sh`: Generates Xcode project (if missing) and builds a signed `.app` bundle.
- `Package.swift`: SPM definition (single executable target).

## Code Style (Swift)

General:
- Prefer clarity over cleverness; keep app-state changes obvious.
- Keep files small; extract subviews / helpers rather than growing a single view file indefinitely.
- Prefer `struct` for models and views; use `class` only for reference semantics (e.g. `ObservableObject`).

Imports:
- One module per line.
- Prefer a stable grouping order rather than random ordering.
- Suggested order for this repo:
  - UI files: `import SwiftUI` (only add others when needed)
  - Non-UI files: `import Foundation`, then other frameworks (`Combine`, `AppKit`, etc.)
- Avoid importing `AppKit` into SwiftUI views unless required.

Formatting:
- Indent: 4 spaces.
- Opening braces on the same line.
- Use trailing commas for multi-line argument lists and collection literals.
- Keep lines reasonably short (aim ~120 chars); wrap long SwiftUI modifier chains vertically.
- Prefer explicit labels for readability (especially in initializers and view modifiers).

Types and access control:
- Use the narrowest visibility that makes sense:
  - `private` for file-internal helpers and state.
  - `fileprivate` only when multiple types in the same file must share an implementation detail.
- Prefer concrete types for state that crosses view boundaries.
- When updating UI-related published state from async work, prefer `@MainActor` isolation or `await MainActor.run { ... }`.

Naming conventions:
- Types/protocols/enums: `UpperCamelCase`.
- Methods/vars: `lowerCamelCase`.
- Boolean properties: `isEnabled`, `hasImages`, `shouldShow…`.
- SwiftUI actions: `selectFolder()`, `navigateToNext()`, `toggleSlideshow()` (imperative verbs).
- Avoid abbreviations unless domain-standard.

SwiftUI patterns:
- Keep `body` readable:
  - Extract subviews into their own `View` structs.
  - Extract computed properties for repeated modifier sets.
- Prefer `@EnvironmentObject` only for truly shared app state; otherwise pass bindings/values.
- Reset view-local state on key changes using `onChange(of:)` (as already done for zoom reset).

State management:
- `AppState` is the single source of truth for:
  - `images`, `currentImageIndex`, sorting, slideshow state, preferences.
- Keep mutations in `AppState` methods; views should call intent methods (do not mutate arrays directly in views).
- When you add new state, also consider persistence (UserDefaults) only if it improves UX.

Error handling and logging:
- Do not silently swallow errors.
- For recoverable failures (e.g. unreadable images), keep behavior user-friendly:
  - Track failures (like `failedImages`) so UI can show a warning.
  - Provide a retry path when reasonable.
- For unexpected errors:
  - Prefer `os.Logger` (or `print` as a last resort in this tiny repo).
  - Include enough context (file URL, operation) to debug.

File and URL handling:
- Use `URL` APIs over string paths.
- Prefer `FileManager` enumerators with explicit options; avoid traversing hidden files.
- Treat user-selected folders as untrusted input; validate extensions and existence.

## Making Changes Safely

- Preserve existing UX unless the task explicitly changes it.
- If you refactor `AppState`, verify:
  - sorting still preserves the current image when possible
  - slideshow timer invalidates correctly
  - preferences load without crashing when keys are missing
- If you add tests:
  - Create `Tests/ImageBrowserTests/` and a corresponding test target in `Package.swift`.
  - Prefer unit tests for pure logic (sorting, preferences encoding/decoding).
  - Avoid UI tests unless required.

## Common Agent Tasks

- Add a feature: implement logic in `AppState.swift` first, then wire UI in `ContentView.swift`.
- Fix a bug: reproduce using `swift run ImageBrowser` (fast) or `./build.sh` (real `.app`).
- Performance: avoid loading full-size images repeatedly; consider caching if needed.
