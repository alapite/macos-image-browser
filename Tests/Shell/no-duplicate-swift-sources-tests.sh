#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

duplicates="$(
    cd "${PROJECT_ROOT}"
    rg --files Sources Tests UITests | rg ' [0-9]+\.swift$' || true
)"

if [ -n "${duplicates}" ]; then
    echo "Tracked duplicate Swift files found:" >&2
    echo "${duplicates}" >&2
    exit 1
fi

echo "no-duplicate-swift-sources-tests.sh: PASS"
