#!/bin/bash

# Build script to create a macOS .app bundle from Swift source files
# Uses XcodeGen for project generation and xcodebuild for compilation

set -euo pipefail

APP_NAME="ImageBrowser"
XCODEPROJ="${APP_NAME}.xcodeproj"
APP_BUNDLE="${APP_NAME}.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.build.XXXXXX")"
STAGED_APP_BUNDLE="${STAGING_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BUILD_DIR=".build"
BUILD_CACHE_DIR=".build-cache"
XCODEBUILD_LOG="${BUILD_DIR}/xcodebuild.log"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MAX_BUILD_SECONDS="${MAX_BUILD_SECONDS:-180}"
CLEAN_MODE="${CLEAN_MODE:-incremental}"
XCODEBUILD_TIMEOUT_SECONDS="${XCODEBUILD_TIMEOUT_SECONDS:-${MAX_BUILD_SECONDS}}"
PROJECT_ROOT="$(pwd)"
XCODE_SOURCE_PACKAGES_DIR="${PROJECT_ROOT}/${BUILD_CACHE_DIR}/source-packages"
LOCAL_HOME="${PROJECT_ROOT}/${BUILD_CACHE_DIR}/local-home"
LOCAL_XDG_CACHE="${PROJECT_ROOT}/${BUILD_CACHE_DIR}/cache"
LOCAL_MODULE_CACHE="${PROJECT_ROOT}/${BUILD_CACHE_DIR}/ModuleCache.noindex"
LOCAL_SWIFTPM_CACHE_DIR="${LOCAL_HOME}/Library/Caches/org.swift.swiftpm"
ISOLATE_XCODE_CACHES="${ISOLATE_XCODE_CACHES:-1}"
DISABLE_AUTOMATIC_PACKAGE_RESOLUTION=0

cleanup_staging_dir() {
    rm -rf "${STAGING_DIR}" 2>/dev/null || true
}

trap cleanup_staging_dir EXIT

if [ "${SIGN_IDENTITY}" = "-" ]; then
    SIGNING_MODE="ad-hoc"
else
    SIGNING_MODE="developer-id"
fi

echo "Building ${APP_NAME}..."
echo "Signing mode: ${SIGNING_MODE}"
echo "Build timeout budget: ${MAX_BUILD_SECONDS}s"
echo "Clean mode: ${CLEAN_MODE}"

build_start_epoch="$(date +%s)"

time_elapsed() {
    local now
    now="$(date +%s)"
    echo $((now - build_start_epoch))
}

time_remaining() {
    local remaining
    remaining=$((MAX_BUILD_SECONDS - $(time_elapsed)))
    if [ "${remaining}" -lt 0 ]; then
        remaining=0
    fi
    echo "${remaining}"
}

enforce_global_timeout() {
    local remaining
    remaining="$(time_remaining)"
    if [ "${remaining}" -le 0 ]; then
        echo "❌ Build exceeded ${MAX_BUILD_SECONDS}s total budget"
        exit 1
    fi
}

latest_rotated_build_dir() {
    find "${PROJECT_ROOT}" -maxdepth 1 -type d -name "${BUILD_DIR}.deleting.*" | sort | tail -n 1
}

seed_source_package_cache() {
    local candidate=""
    mkdir -p "${BUILD_CACHE_DIR}"

    if [ -d "${XCODE_SOURCE_PACKAGES_DIR}/repositories" ] || [ -d "${XCODE_SOURCE_PACKAGES_DIR}/checkouts" ]; then
        return
    fi

    rm -rf "${XCODE_SOURCE_PACKAGES_DIR}"

    for candidate in \
        "${BUILD_DIR}/SourcePackages" \
        "$(latest_rotated_build_dir)/SourcePackages" \
        "${BUILD_DIR}/checkouts" \
        "$(latest_rotated_build_dir)/checkouts"
    do
        if [ -n "${candidate}" ] && [ -d "${candidate}" ] && { [ -d "${candidate}/repositories" ] || [ -d "${candidate}/checkouts" ]; }; then
            echo "Preserving source packages from ${candidate}"
            mv "${candidate}" "${XCODE_SOURCE_PACKAGES_DIR}"
            return
        fi
    done

    mkdir -p "${XCODE_SOURCE_PACKAGES_DIR}"
}

if [ "${SIGNING_MODE}" = "developer-id" ]; then
    if ! security find-identity -v -p codesigning | grep -F "${SIGN_IDENTITY}" > /dev/null; then
        echo "❌ Error: Requested SIGN_IDENTITY not found in keychain"
        echo "   SIGN_IDENTITY=${SIGN_IDENTITY}"
        echo "   Available identities:"
        security find-identity -v -p codesigning || true
        exit 1
    fi
fi

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "${APP_BUNDLE}"
seed_source_package_cache
"${PROJECT_ROOT}/scripts/prepare-build-dir.sh" "${CLEAN_MODE}" "${BUILD_DIR}"
# Remove common stale lock/db artifacts that can block SwiftPM/Xcode build graph setup.
rm -f "${BUILD_DIR}"/.lock* \
      "${BUILD_DIR}"/build*.db \
      "${BUILD_DIR}"/build*.db-shm \
      "${BUILD_DIR}"/build*.db-wal
enforce_global_timeout

# Regenerate Xcode project from spec on every run so path/config changes are picked up
echo "Generating Xcode project..."
xcodegen generate --spec project.yml
DISABLE_AUTOMATIC_PACKAGE_RESOLUTION="$(
    "${PROJECT_ROOT}/scripts/prepare-xcode-package-resolution.sh" "${PROJECT_ROOT}" "${XCODEPROJ}" | tail -n 1
)"
if [ "${DISABLE_AUTOMATIC_PACKAGE_RESOLUTION}" = "1" ]; then
    echo "Using pinned package resolution from Xcode workspace Package.resolved"
else
    echo "Allowing xcodebuild to resolve packages because a complete local lockfile/cache set is not available"
fi
enforce_global_timeout

# Build the project for both architectures using xcodebuild
echo "Building Xcode project (x86_64 + arm64)..."
remaining_before_xcodebuild="$(time_remaining)"
if [ "${remaining_before_xcodebuild}" -lt "${XCODEBUILD_TIMEOUT_SECONDS}" ]; then
    XCODEBUILD_TIMEOUT_SECONDS="${remaining_before_xcodebuild}"
fi
if [ "${XCODEBUILD_TIMEOUT_SECONDS}" -le 0 ]; then
    echo "❌ No time remaining for xcodebuild phase"
    exit 1
fi
echo "xcodebuild timeout: ${XCODEBUILD_TIMEOUT_SECONDS}s"
mkdir -p "${BUILD_DIR}"
: > "${XCODEBUILD_LOG}"
mkdir -p \
    "${LOCAL_HOME}/Library/Caches" \
    "${LOCAL_XDG_CACHE}" \
    "${LOCAL_MODULE_CACHE}" \
    "${LOCAL_SWIFTPM_CACHE_DIR}" \
    "${XCODE_SOURCE_PACKAGES_DIR}/repositories" \
    "${XCODE_SOURCE_PACKAGES_DIR}/checkouts"

ln -sfn "${XCODE_SOURCE_PACKAGES_DIR}/repositories" "${LOCAL_SWIFTPM_CACHE_DIR}/repositories"

run_xcodebuild_command() {
    if [ "${ISOLATE_XCODE_CACHES}" = "1" ]; then
        "${PROJECT_ROOT}/scripts/run-xcodebuild-isolated.sh" \
            "${LOCAL_HOME}" \
            "${LOCAL_XDG_CACHE}" \
            "${LOCAL_MODULE_CACHE}" \
            xcodebuild "$@"
    else
        xcodebuild "$@"
    fi
}

xcodebuild_args=(
    -project "${XCODEPROJ}"
    -scheme "${APP_NAME}"
    -configuration Release
    -destination "platform=macOS"
    -derivedDataPath "${BUILD_DIR}"
    -clonedSourcePackagesDirPath "${XCODE_SOURCE_PACKAGES_DIR}"
)

if [ "${DISABLE_AUTOMATIC_PACKAGE_RESOLUTION}" = "1" ]; then
    xcodebuild_args+=(-disableAutomaticPackageResolution)
fi

xcodebuild_args+=(
    build
    CODE_SIGN_IDENTITY="-"
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
    ARCHS="x86_64 arm64"
    VALID_ARCHS="x86_64 arm64"
)

if [ "${ISOLATE_XCODE_CACHES}" = "1" ]; then
    run_xcodebuild_command "${xcodebuild_args[@]}" > "${XCODEBUILD_LOG}" 2>&1 &
else
    run_xcodebuild_command "${xcodebuild_args[@]}" > "${XCODEBUILD_LOG}" 2>&1 &
fi

xcodebuild_pid=$!
elapsed=0

while kill -0 "${xcodebuild_pid}" 2>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    echo "… xcodebuild still running (${elapsed}s elapsed, total $(time_elapsed)s)"
    tail -3 "${XCODEBUILD_LOG}" || true

    if [ "${elapsed}" -ge "${XCODEBUILD_TIMEOUT_SECONDS}" ]; then
        echo "❌ xcodebuild timed out after ${XCODEBUILD_TIMEOUT_SECONDS}s"
        kill "${xcodebuild_pid}" 2>/dev/null || true
        wait "${xcodebuild_pid}" 2>/dev/null || true
        echo "Last 120 log lines:"
        tail -120 "${XCODEBUILD_LOG}" || true
        exit 1
    fi
    enforce_global_timeout
done

set +e
wait "${xcodebuild_pid}"
xcodebuild_status=$?
set -e

if [ "${xcodebuild_status}" -eq 0 ]; then
    echo "✓ xcodebuild succeeded (last 20 lines):"
    tail -20 "${XCODEBUILD_LOG}"
else
    echo "❌ xcodebuild failed (last 120 lines):"
    tail -120 "${XCODEBUILD_LOG}"
    exit 1
fi
enforce_global_timeout

# Find the built app bundle.
# Avoid recursive search over the entire derived data tree because it can be very slow.
echo "Locating built app bundle..."
BUILT_APP=""
for candidate in \
    "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" \
    "${BUILD_DIR}/Build/Products/Debug/${APP_NAME}.app"
do
    if [ -d "${candidate}" ]; then
        BUILT_APP="${candidate}"
        break
    fi
done

if [ -z "${BUILT_APP}" ]; then
    BUILT_APP=$(find "${BUILD_DIR}/Build/Products" -maxdepth 4 -name "${APP_NAME}.app" -type d | head -1)
fi

if [ -z "${BUILT_APP}" ]; then
    echo "❌ Error: Could not find built app bundle"
    exit 1
fi

echo "Copying app bundle to current directory..."
echo "Staging app bundle outside the workspace for signing..."
COPYFILE_DISABLE=1 ditto --noqtn --norsrc "${BUILT_APP}" "${STAGED_APP_BUNDLE}"
enforce_global_timeout

# Ensure icon payload from Assets.xcassets is present in the packaged app.
ASSET_CAR_PATH="${STAGED_APP_BUNDLE}/Contents/Resources/Assets.car"
if [ ! -f "${ASSET_CAR_PATH}" ]; then
    echo "❌ Missing asset catalog payload: ${ASSET_CAR_PATH}"
    echo "   App icon resources were not compiled into the app bundle."
    echo "   Check project.yml resource wiring for Sources/ImageBrowser/Assets.xcassets."
    echo "   Contents of app Resources directory:"
    ls -la "${STAGED_APP_BUNDLE}/Contents/Resources" || true
    exit 1
fi
echo "✓ Asset catalog payload found: ${ASSET_CAR_PATH}"

# Remove extended attributes that can cause code signing issues
echo "Cleaning extended attributes..."
"${PROJECT_ROOT}/scripts/strip-bundle-xattrs.sh" "${STAGED_APP_BUNDLE}"

# Code sign the app bundle
echo "Code signing app bundle..."
if [ "${SIGNING_MODE}" = "developer-id" ]; then
    codesign --force --deep --timestamp --options runtime --sign "${SIGN_IDENTITY}" "${STAGED_APP_BUNDLE}"
else
    codesign --force --deep --sign - "${STAGED_APP_BUNDLE}"
fi
enforce_global_timeout

echo "Copying signed app bundle to current directory..."
COPYFILE_DISABLE=1 ditto --noqtn --norsrc "${STAGED_APP_BUNDLE}" "${APP_BUNDLE}"
enforce_global_timeout

# Verify the app bundle
echo "Verifying app bundle..."
codesign -dvvv --deep "${APP_BUNDLE}" > /dev/null 2>&1 && echo "✓ Code signing verified" || echo "⚠ Code signing has warnings"

if [ "${SIGNING_MODE}" = "developer-id" ]; then
    echo "Checking Gatekeeper assessment..."
    if spctl -a -vv "${APP_BUNDLE}" > /dev/null 2>&1; then
        echo "✓ Gatekeeper accepted"
    else
        echo "⚠ Gatekeeper rejected (usually means notarization is still required)"
    fi
fi

# Check if universal binary
if file "${CONTENTS_DIR}/MacOS/${APP_NAME}" | grep -q "universal"; then
    echo "✓ Universal binary confirmed (x86_64 + arm64)"
else
    echo "⚠ Warning: Binary may not be universal"
fi

echo ""
echo "✓ Build complete!"
echo "✓ App bundle created: ${APP_BUNDLE}"
echo ""
echo "To run the app:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "Tip: CLEAN_MODE=full ./build.sh for a full DerivedData wipe."
echo "Tip: CLEAN_MODE=fast ./build.sh to rebuild from clean products only."
echo "Tip: ISOLATE_XCODE_CACHES=1 ./build.sh to force local cache/home paths."
echo ""
echo "Or double-click ${APP_BUNDLE} in Finder"
if [ "${SIGNING_MODE}" = "developer-id" ]; then
    echo ""
    echo "Signed with Developer ID identity: ${SIGN_IDENTITY}"
    echo "If Gatekeeper still rejects, notarize the app before distribution."
fi
