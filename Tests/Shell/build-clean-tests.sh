#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/build-clean-tests.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_exists() {
    local path="$1"
    if [ ! -e "${path}" ]; then
        echo "Expected path to exist: ${path}" >&2
        exit 1
    fi
}

assert_not_exists() {
    local path="$1"
    if [ -e "${path}" ]; then
        echo "Expected path to be absent: ${path}" >&2
        exit 1
    fi
}

assert_less_than() {
    local actual="$1"
    local threshold="$2"
    if [ "${actual}" -ge "${threshold}" ]; then
        echo "Expected ${actual} to be less than ${threshold}" >&2
        exit 1
    fi
}

wait_for_absence() {
    local path="$1"
    local deadline="$((SECONDS + 10))"
    while [ -e "${path}" ] && [ "${SECONDS}" -lt "${deadline}" ]; do
        sleep 0.2
    done

    assert_not_exists "${path}"
}

test_full_clean_rotates_build_dir_without_waiting_for_delete() {
    local workspace="${TEST_ROOT}/workspace"
    local build_dir="${workspace}/.build"
    mkdir -p "${build_dir}/nested"
    echo "payload" > "${build_dir}/nested/file.txt"

    local start_time end_time elapsed
    start_time="$(date +%s)"
    BUILD_DIR_DELETE_SLEEP_SECONDS=2 \
        "${PROJECT_ROOT}/scripts/prepare-build-dir.sh" full "${build_dir}" > "${workspace}/output.log"
    end_time="$(date +%s)"
    elapsed="$((end_time - start_time))"

    assert_less_than "${elapsed}" 2
    assert_exists "${build_dir}"

    local rotated_dir
    rotated_dir="$(find "${workspace}" -maxdepth 1 -type d -name '.build.deleting.*' | head -n 1)"
    assert_exists "${rotated_dir}"

    wait_for_absence "${rotated_dir}"

    if ! grep -q "scheduled background deletion" "${workspace}/output.log"; then
        echo "Expected scheduled background deletion message" >&2
        exit 1
    fi
}

test_invalid_mode_fails() {
    local workspace="${TEST_ROOT}/invalid"
    mkdir -p "${workspace}"

    if "${PROJECT_ROOT}/scripts/prepare-build-dir.sh" invalid "${workspace}/.build" >/dev/null 2>&1; then
        echo "Expected invalid mode to fail" >&2
        exit 1
    fi
}

test_full_clean_rotates_build_dir_without_waiting_for_delete
test_invalid_mode_fails

echo "build-clean-tests.sh: PASS"
