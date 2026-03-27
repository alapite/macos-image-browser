#!/bin/bash

set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <local-home> <local-cache> <module-cache> <command...>" >&2
    exit 1
fi

local_home="$1"
local_cache="$2"
module_cache="$3"
shift 3

mkdir -p "${local_home}/Library/Caches" "${local_cache}" "${module_cache}"

if [ "${PRINT_ONLY:-0}" = "1" ]; then
    printf 'CFFIXED_USER_HOME=%s\n' "${local_home}"
    printf 'HOME=%s\n' "${local_home}"
    printf 'XDG_CACHE_HOME=%s\n' "${local_cache}"
    printf 'CLANG_MODULE_CACHE_PATH=%s\n' "${module_cache}"
    printf 'SWIFTPM_MODULECACHE_OVERRIDE=%s\n' "${module_cache}"
    printf '%s\n' "$*"
    exit 0
fi

env \
    CFFIXED_USER_HOME="${local_home}" \
    HOME="${local_home}" \
    XDG_CACHE_HOME="${local_cache}" \
    CLANG_MODULE_CACHE_PATH="${module_cache}" \
    SWIFTPM_MODULECACHE_OVERRIDE="${module_cache}" \
    "$@"
