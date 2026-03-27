#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/prepare-xcode-package-resolution-tests.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_exists() {
    local path="$1"
    if [ ! -e "${path}" ]; then
        echo "Expected path to exist: ${path}" >&2
        exit 1
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    if [ "${expected}" != "${actual}" ]; then
        echo "Expected '${expected}', got '${actual}'" >&2
        exit 1
    fi
}

test_seeds_workspace_package_resolved_from_root() {
    local workspace="${TEST_ROOT}/seeded"
    local xcodeproj="ImageBrowser.xcodeproj"
    mkdir -p "${workspace}/${xcodeproj}/project.xcworkspace"
    cat > "${workspace}/Package.resolved" <<'EOF'
{
  "pins" : [],
  "version" : 2
}
EOF

    local output
    output="$("${PROJECT_ROOT}/scripts/prepare-xcode-package-resolution.sh" "${workspace}" "${xcodeproj}")"

    assert_exists "${workspace}/${xcodeproj}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    assert_equals "0" "$(printf '%s\n' "${output}" | tail -n 1)"
}

test_disables_automatic_resolution_when_package_cache_exists() {
    local workspace="${TEST_ROOT}/cached"
    local xcodeproj="ImageBrowser.xcodeproj"
    mkdir -p "${workspace}/${xcodeproj}/project.xcworkspace"
    mkdir -p "${workspace}/.build-cache/source-packages/repositories/grdb.swift"
    cat > "${workspace}/Package.resolved" <<'EOF'
{
  "pins" : [],
  "version" : 2
}
EOF

    local output
    output="$("${PROJECT_ROOT}/scripts/prepare-xcode-package-resolution.sh" "${workspace}" "${xcodeproj}")"

    assert_equals "1" "$(printf '%s\n' "${output}" | tail -n 1)"
}

test_allows_automatic_resolution_without_lockfile() {
    local workspace="${TEST_ROOT}/unseeded"
    local xcodeproj="ImageBrowser.xcodeproj"
    mkdir -p "${workspace}/${xcodeproj}/project.xcworkspace"

    local output
    output="$("${PROJECT_ROOT}/scripts/prepare-xcode-package-resolution.sh" "${workspace}" "${xcodeproj}")"

    assert_equals "0" "$(printf '%s\n' "${output}" | tail -n 1)"
}

test_seeds_workspace_package_resolved_from_root
test_disables_automatic_resolution_when_package_cache_exists
test_allows_automatic_resolution_without_lockfile

echo "prepare-xcode-package-resolution-tests.sh: PASS"
