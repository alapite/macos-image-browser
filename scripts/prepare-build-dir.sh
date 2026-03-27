#!/bin/bash

set -euo pipefail

clean_mode="${1:-}"
build_dir="${2:-}"

if [ -z "${clean_mode}" ] || [ -z "${build_dir}" ]; then
    echo "Usage: $0 <incremental|fast|full> <build-dir>" >&2
    exit 1
fi

delete_in_background() {
    local target_dir="$1"
    local delete_delay_seconds="${BUILD_DIR_DELETE_SLEEP_SECONDS:-0}"

    (
        if [ "${delete_delay_seconds}" -gt 0 ]; then
            sleep "${delete_delay_seconds}"
        fi
        rm -rf "${target_dir}"
    ) >/dev/null 2>&1 &
}

case "${clean_mode}" in
  incremental)
    echo "Incremental clean: preserving ${build_dir} products for fastest rebuilds"
    ;;
  fast)
    echo "Fast clean: removing build products only"
    rm -rf "${build_dir}/Build" \
           "${build_dir}/Logs" \
           "${build_dir}/xcodebuild.log"
    ;;
  full)
    if [ -d "${build_dir}" ] || [ -L "${build_dir}" ]; then
        rotating_dir="${build_dir}.deleting.$(date +%s).$$"
        echo "Full clean: rotating ${build_dir} -> ${rotating_dir}"
        mv "${build_dir}" "${rotating_dir}"
        mkdir -p "${build_dir}"
        delete_in_background "${rotating_dir}"
        echo "Full clean: scheduled background deletion of ${rotating_dir}"
    else
        echo "Full clean: ${build_dir} already absent"
    fi
    ;;
  *)
    echo "❌ Invalid CLEAN_MODE: ${clean_mode} (expected: incremental|fast|full)" >&2
    exit 1
    ;;
esac
