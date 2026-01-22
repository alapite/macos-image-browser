# Testing Patterns

**Analysis Date:** 2026-01-21

## Test Framework

**Runner:**
- SwiftPM test runner (`swift test`) - present, but no test targets are defined (`Package.swift`).

**Assertion Library:**
- XCTest - Not detected in repo sources (no `import XCTest`).

**Run Commands:**
```bash
swift test                  # Run all tests (currently: "no tests found")
swift test list             # List tests (once tests exist)
swift test --filter "..."  # Run a single test (once tests exist)
```

## Test File Organization

**Location:**
- Not detected (no `Tests/` directory in repo).

**Naming:**
- Not applicable yet.

**Structure:**
```text
Not detected
```

## Test Structure

**Suite Organization:**
- Not detected (no test files).

**Patterns:**
- Not detected.

## Mocking

**Framework:**
- Not detected.

## Fixtures and Factories

**Test Data:**
- Not detected.

## Coverage

**Requirements:**
- Not detected.

## Test Types

**Unit Tests:**
- Not present.

**Integration Tests:**
- Not present.

**E2E Tests:**
- Not present.

## Common Patterns

**Recommended initial targets for tests (based on pure logic):**
- Sorting behavior and custom ordering (`AppState.swift`).
- Preferences encode/decode and backward compatibility (`AppState.swift`).

---

*Testing analysis: 2026-01-21*
*Update when test patterns change*
