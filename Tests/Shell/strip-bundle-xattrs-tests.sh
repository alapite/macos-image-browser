#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/strip-bundle-xattrs-tests.XXXXXX")"
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
    "${PROJECT_ROOT}/scripts/strip-bundle-xattrs.sh" \
    "${TEST_ROOT}/ImageBrowser.app"
)"

assert_contains "${output}" "xattr -cr ${TEST_ROOT}/ImageBrowser.app"
assert_contains "${output}" "find ${TEST_ROOT}/ImageBrowser.app -type d \\( -name *.app -o -name *.bundle \\) -print"
assert_contains "${output}" "com.apple.FinderInfo"
assert_contains "${output}" "com.apple.fileprovider.fpfs#P"
assert_contains "${output}" "com.apple.macl"
assert_contains "${output}" "com.apple.provenance"

echo "strip-bundle-xattrs-tests.sh: PASS"
