# Technology Stack

**Analysis Date:** 2026-01-21

## Languages

**Primary:**
- Swift (Swift tools 5.9) - All application code (`ImageBrowserApp.swift`, `ContentView.swift`, `AppState.swift`, `Package.swift`)

**Secondary:**
- Bash - Build automation (`build.sh`)
- YAML - XcodeGen project spec (`project.yml`)
- Property List (XML) - App metadata / permission strings (`Info.plist`)

## Runtime

**Environment:**
- macOS 13+ - App runtime target (`Package.swift`)
- Xcode toolchain 15.x - Required to build the .app bundle (`project.yml`, `build.sh`)
- SwiftPM - Fast local iteration (`Package.swift`)

**Package Manager:**
- Swift Package Manager (SPM) - `Package.swift`
- Lockfile: Not detected (no `Package.resolved` in repo)

## Frameworks

**Core:**
- SwiftUI - UI framework (`ImageBrowserApp.swift`, `ContentView.swift`)
- Combine - Observable state (`AppState.swift`)
- Foundation - URLs, filesystem, timers, UserDefaults (`AppState.swift`)
- AppKit - macOS-specific UI + image loading (`AppState.swift`, `ContentView.swift`)

**Testing:**
- XCTest / SwiftPM tests - Not detected (no test target in `Package.swift`, no `Tests/` directory)

**Build/Dev:**
- XcodeGen - Project generation (`build.sh`, `project.yml`)
- xcodebuild - Release build (`build.sh`)
- codesign - Ad-hoc signing for local app bundle (`build.sh`)

## Key Dependencies

**Critical:**
- None (no external SPM dependencies) (`Package.swift`)

**Infrastructure:**
- Apple system frameworks only (SwiftUI, Combine, Foundation, AppKit) (`*.swift`)

## Configuration

**Environment:**
- No `.env` / environment-variable based runtime config detected
- Preferences persisted to `UserDefaults` under key `ImageBrowserPreferences` (`AppState.swift`)

**Build:**
- SwiftPM target definition: `Package.swift`
- XcodeGen project definition: `project.yml`
- Build script: `build.sh`
- App plist (includes folder access usage descriptions): `Info.plist`

## Platform Requirements

**Development:**
- macOS 13+
- Xcode 15+ installed (for SDK + `xcodebuild`)
- Optional: Homebrew (used by `build.sh` to install XcodeGen)

**Production:**
- Local macOS app (no server component)
- Distribution model not defined in repo (no notarization / App Store pipeline detected)

---

*Stack analysis: 2026-01-21*
*Update after major dependency changes*
