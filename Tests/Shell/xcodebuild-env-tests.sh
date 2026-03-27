#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xcodebuild-env-tests.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "Expected output to contain: ${needle}" >&2
        exit 1
    fi
}

output="$(
    PRINT_ONLY=1 \
    "${PROJECT_ROOT}/scripts/run-xcodebuild-isolated.sh" \
    "${TEST_ROOT}/home" \
    "${TEST_ROOT}/cache" \
    "${TEST_ROOT}/modules" \
    xcodebuild -project ImageBrowser.xcodeproj -scheme ImageBrowser build
)"

assert_contains "${output}" "CFFIXED_USER_HOME=${TEST_ROOT}/home"
assert_contains "${output}" "HOME=${TEST_ROOT}/home"
assert_contains "${output}" "XDG_CACHE_HOME=${TEST_ROOT}/cache"
assert_contains "${output}" "CLANG_MODULE_CACHE_PATH=${TEST_ROOT}/modules"
assert_contains "${output}" "SWIFTPM_MODULECACHE_OVERRIDE=${TEST_ROOT}/modules"
assert_contains "${output}" "xcodebuild -project ImageBrowser.xcodeproj -scheme ImageBrowser build"

echo "xcodebuild-env-tests.sh: PASS"
