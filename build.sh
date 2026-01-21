#!/bin/bash

# Build script to create a macOS .app bundle from Swift source files
# Uses XcodeGen for project generation and xcodebuild for compilation

set -e

APP_NAME="ImageBrowser"
XCODEPROJ="${APP_NAME}.xcodeproj"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BUILD_DIR=".build"

echo "Building ${APP_NAME}..."

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf "${APP_BUNDLE}"
rm -rf "${BUILD_DIR}"

# Generate Xcode project if needed
if [ ! -d "${XCODEPROJ}" ]; then
    echo "Generating Xcode project..."
    xcodegen generate
fi

# Build the project for both architectures using xcodebuild
echo "Building Xcode project (x86_64 + arm64)..."
xcodebuild \
    -project "${XCODEPROJ}" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "${BUILD_DIR}" \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS="x86_64 arm64" \
    VALID_ARCHS="x86_64 arm64" \
    2>&1 | tail -20

# Find the built app bundle
BUILT_APP=$(find "${BUILD_DIR}" -name "${APP_NAME}.app" -type d | head -1)

if [ -z "${BUILT_APP}" ]; then
    echo "❌ Error: Could not find built app bundle"
    exit 1
fi

echo "Copying app bundle to current directory..."
cp -R "${BUILT_APP}" "${APP_BUNDLE}"

# Remove extended attributes that can cause code signing issues
echo "Cleaning extended attributes..."
xattr -rc "${APP_BUNDLE}" 2>/dev/null || true
xattr -dr com.apple.provenance "${APP_BUNDLE}" 2>/dev/null || true

# Code sign the app bundle
echo "Code signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# Verify the app bundle
echo "Verifying app bundle..."
codesign -dvvv --deep "${APP_BUNDLE}" > /dev/null 2>&1 && echo "✓ Code signing verified" || echo "⚠ Code signing has warnings"

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
echo "Or double-click ${APP_BUNDLE} in Finder"
