#!/bin/bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <project-root> <xcodeproj>" >&2
    exit 1
fi

project_root="$1"
xcodeproj="$2"

root_package_resolved="${project_root}/Package.resolved"
workspace_swiftpm_dir="${project_root}/${xcodeproj}/project.xcworkspace/xcshareddata/swiftpm"
workspace_package_resolved="${workspace_swiftpm_dir}/Package.resolved"
source_packages_dir="${project_root}/.build-cache/source-packages"
source_package_repositories_dir="${source_packages_dir}/repositories"
source_package_checkouts_dir="${source_packages_dir}/checkouts"

mkdir -p "${workspace_swiftpm_dir}"

if [ -f "${root_package_resolved}" ]; then
    if [ ! -f "${workspace_package_resolved}" ] || ! cmp -s "${root_package_resolved}" "${workspace_package_resolved}"; then
        cp "${root_package_resolved}" "${workspace_package_resolved}"
        echo "Synchronized Xcode workspace Package.resolved from root Package.resolved"
    fi
fi

if [ -f "${workspace_package_resolved}" ]; then
    if find "${source_package_repositories_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        echo "1"
        exit 0
    fi

    if find "${source_package_checkouts_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        echo "1"
        exit 0
    fi

    echo "Xcode workspace Package.resolved is present, but no local source package cache was found"
    echo "0"
    exit 0
fi

if [ -f "${root_package_resolved}" ]; then
    echo "Root Package.resolved is present, but xcodebuild will need to resolve packages to populate cache"
    echo "0"
    exit 0
fi

echo "0"
