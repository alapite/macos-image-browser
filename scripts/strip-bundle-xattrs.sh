#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <app-bundle>" >&2
    exit 1
fi

bundle_path="$1"
attrs=(
    "com.apple.FinderInfo"
    "com.apple.fileprovider.fpfs#P"
    "com.apple.macl"
    "com.apple.provenance"
)

if [ "${PRINT_ONLY:-0}" = "1" ]; then
    printf 'xattr -cr %s\n' "${bundle_path}"
    printf 'find %s -type d \\( -name *.app -o -name *.bundle \\) -print\n' "${bundle_path}"
    for attr in "${attrs[@]}"; do
        printf 'xattr -d %s <bundle-dir>\n' "${attr}"
        printf 'xattr -dr %s %s\n' "${attr}" "${bundle_path}"
        printf 'find %s -exec xattr -d %s {} +\n' "${bundle_path}" "${attr}"
    done
    exit 0
fi

xattr -cr "${bundle_path}" 2>/dev/null || true

bundle_dirs=("${bundle_path}")
while IFS= read -r nested_bundle; do
    bundle_dirs+=("${nested_bundle}")
done < <(find "${bundle_path}" -type d \( -name "*.app" -o -name "*.bundle" \) -print 2>/dev/null)

for attr in "${attrs[@]}"; do
    for bundle_dir in "${bundle_dirs[@]}"; do
        xattr -d "${attr}" "${bundle_dir}" 2>/dev/null || true
    done
    xattr -dr "${attr}" "${bundle_path}" 2>/dev/null || true
    find "${bundle_path}" -exec xattr -d "${attr}" {} + 2>/dev/null || true
done
