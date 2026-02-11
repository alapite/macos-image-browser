# Agent Instructions (macos-image-browser)

This repository is a SwiftUI macOS image browser with:
- Swift Package Manager support for fast local build/test cycles.
- XcodeGen + `xcodebuild` support (via `build.sh`) for a signed `.app` bundle.

## Rules Files (Cursor / Copilot)

Checked in this repository:
- No `.cursorrules` file found.
- No `.cursor/rules/` directory found.
- No `.github/copilot-instructions.md` file found.

If any of these files are added later, agents should treat them as higher-priority local instructions.

## Environment and Prerequisites

- macOS 13+
- Xcode installed (for SDKs, `xcodebuild`, XCTest runtime)
- Swift 5.9 toolchain (as declared in `Package.swift`)
- Homebrew recommended (`build.sh` installs XcodeGen if missing)

## Build and Run Commands

SwiftPM (fast iteration):
- Build: `swift build`
- Run executable: `swift run ImageBrowser`
- Clean build artifacts: `rm -rf .build`
- Inspect package graph: `swift package dump-package`

XcodeGen / app bundle path:
- Generate project: `xcodegen generate`
- Build signed app bundle: `./build.sh`
- Run built app: `open ImageBrowser.app`

Direct `xcodebuild` (when project exists):
- `xcodebuild -project ImageBrowser.xcodeproj -scheme ImageBrowser -configuration Release -destination "platform=macOS" build`

## Test Commands

Current status:
- Unit tests exist under `Tests/ImageBrowserTests`.
- CI currently runs `swift test` on macOS (`.github/workflows/ci.yml`).

SwiftPM tests (primary path):
- Run all tests: `swift test`
- List all tests: `swift test list`
- Run one test case: `swift test --filter "ImageBrowserTests.AppStateTests"`
- Run one test method: `swift test --filter "ImageBrowserTests.AppStateTests/testSortByName_ordersAlphabetically"`

Notes for `swift test` in this repo:
- You may see package warnings about unhandled top-level files (for example `AGENTS.md` or `UITests`).
- You may also see Swift 6 sendability warnings from `AppState.swift`.
- These are warnings (not current test failures) unless treated as errors by a stricter toolchain.

Xcode test equivalents:
- Run all tests in scheme: `xcodebuild test -project ImageBrowser.xcodeproj -scheme ImageBrowser -destination "platform=macOS"`
- Run one test method: `xcodebuild test -project ImageBrowser.xcodeproj -scheme ImageBrowser -destination "platform=macOS" -only-testing:ImageBrowserTests/AppStateTests/testSortByName_ordersAlphabetically`
- Run UI test scheme: `xcodebuild test -project ImageBrowser.xcodeproj -scheme ImageBrowserUITests -destination "platform=macOS"`

## Lint and Formatting

Current status:
- No enforced lint step in CI beyond compilation/test.
- No repo-local `.swiftformat` or `.swiftlint.yml` config currently present.

Optional local tools:
- Format: `swiftformat .`
- Lint: `swiftlint`

If you add lint/format tooling:
- Commit config files with defaults appropriate to this codebase.
- Update this document and CI workflow with exact commands.

## Project Layout

- `ImageBrowserApp.swift`: `@main` entrypoint, window setup.
- `ContentView.swift`: main UI, sidebar, viewer, settings sheets.
- `AppState.swift`: source of truth for image list, navigation, sort, slideshow, caching, persistence.
- `AppDependencies.swift`: protocols + adapters for filesystem and preferences (test seams).
- `Tests/ImageBrowserTests/*.swift`: unit/integration-style tests for app state and enumeration.
- `UITests/ImageBrowserUITests.swift`: UI test target source.
- `Package.swift`: SwiftPM package + executable and test targets.
- `project.yml`: XcodeGen project and scheme definitions.
- `build.sh`: app bundle build/sign script.

## Code Style Guidelines (Swift)

General:
- Prefer straightforward, explicit code over abstractions that hide behavior.
- Keep mutable app behavior in `AppState`; views should call intent methods.
- Prefer extraction of focused helpers/subviews over growing large monolithic blocks.

Imports:
- One import per line.
- Keep order stable and intention-revealing.
- Preferred ordering in this repo:
  - UI files: `SwiftUI` first, then platform frameworks only when needed.
  - Non-UI files: `Foundation` first, then others (`Combine`, `AppKit`, `ImageIO`, `os`).
- Do not add `AppKit` to SwiftUI files unless API needs it.

Formatting:
- 4-space indentation; no tabs.
- Braces on same line.
- Favor trailing commas in multiline literals/argument lists.
- Keep lines readable (target around 120 chars).
- Wrap long SwiftUI modifier chains vertically.

Types and access control:
- `struct` by default; use `class` for shared mutable/reference semantics (`ObservableObject`, coordinators).
- Use the narrowest access: prefer `private`, then `fileprivate` only when needed.
- Keep protocols small and capability-based (see `FileSystemProviding`, `PreferencesStore`).

State and concurrency:
- UI-observed state should stay `@Published` on `AppState`.
- When crossing async boundaries, update UI state on the main actor.
- Cancel and replace long-running tasks when inputs change (pattern used for thumbnail prefetch).
- Be mindful of sendability warnings when capturing Foundation/AppKit reference types in concurrent closures.

Naming:
- Types: `UpperCamelCase`.
- Variables/functions/properties: `lowerCamelCase`.
- Boolean names should read as predicates (`isLoadingImages`, `isSlideshowRunning`).
- Action methods should use verbs (`loadImages`, `navigateToNext`, `updateCustomOrder`).

Error handling and logging:
- Do not silently ignore unexpected failures.
- For recoverable issues (bad/corrupt image), track state for user-visible feedback (`failedImages`).
- Prefer structured logging with `Logger`/`OSSignposter` (`Logging.swift`) over ad-hoc prints.
- Include operation context (URL/path/action) in diagnostics.

File and URL handling:
- Use `URL` and `FileManager` APIs, not string concatenation for paths.
- Skip hidden files when enumerating folders unless behavior explicitly changes.
- Validate user-selected paths/extensions before processing.

Testing expectations:
- Add or update tests for behavior changes in sorting, navigation, slideshow, loading, or persistence.
- Prefer focused XCTest methods with descriptive names and Given/When/Then comments.
- Keep fixtures in `Tests/Fixtures` and shared helpers in `Tests/ImageBrowserTests/TestUtilities.swift`.

## Safety Checklist for Agents

- Preserve existing UX unless change request says otherwise.
- If editing `AppState`, re-check sorting stability, slideshow lifecycle, and preference load/save behavior.
- Before finishing substantial work, run at least targeted tests (or `swift test` for broader changes).
- If you introduce new build/test/lint commands, document them here immediately.
