# ImageBrowser

A native macOS image-browsing application built with Swift and SwiftUI.

## Features

### 1. Folder Selection and Image Browsing
- Select any folder to browse all images within it and its subfolders
- Supports common image formats: JPG, JPEG, PNG, GIF, BMP, TIFF, WebP, HEIC
- Automatically scans and loads all images from the selected directory

### 2. Image Navigation
- **Manual Navigation**: Use Previous/Next buttons or click on thumbnails in the sidebar
- **Slideshow Mode**: Automatically cycle through images with configurable timing
- Slideshow interval can be adjusted from 1 to 10 seconds
- Visual indicator shows slideshow status and current interval

### 3. Image Sorting Options
- **By Name**: Sort images alphabetically by filename
- **By Creation Date**: Sort images by when they were created
- **Custom Order**: Define your own sequence by dragging and reordering images

### 4. Additional Features
- Thumbnail sidebar for quick navigation
- Zoom and pan functionality (drag to pan, scroll/pinch to zoom, double-click to reset)
- Image information overlay showing filename and position
- Preferences persistence (remembers your settings between sessions)
- Dark-themed interface for comfortable viewing

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (or Swift 5.9+)

## Quick Start - Building the App

### Option 1: Using the Build Script (Recommended)

The easiest way to build the app is using the provided build script:

```bash
# Make the script executable (first time only)
chmod +x build.sh

# Build the app
./build.sh
```

Optional: sign with a Developer ID certificate instead of ad-hoc signing:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

This will create an `ImageBrowser.app` bundle in the current directory. You can then:

- **Double-click** `ImageBrowser.app` in Finder to launch it
- Or run from terminal: `open ImageBrowser.app`

Notes:
- The script regenerates `ImageBrowser.xcodeproj` from `project.yml` on each run.
- Full `xcodebuild` output is written to `.build/xcodebuild.log`.
- Without `SIGN_IDENTITY`, the app is ad-hoc signed (good for local use).
- With `SIGN_IDENTITY`, the app is signed with Developer ID and checked by `spctl`; notarization is still required for broad Gatekeeper trust.

### Option 2: Using Xcode

1. Generate the Xcode project:

```bash
xcodegen generate --spec project.yml
```

2. Open `ImageBrowser.xcodeproj` in Xcode.
3. Build and run (⌘R).

### Option 3: Using Swift Package Manager

```bash
# Build the project
swift build

# Run the executable
swift run
```

## Usage

### Getting Started

1. Launch the application (double-click `ImageBrowser.app`)
2. Click the "Open Folder" button in the toolbar
3. Select a folder containing images
4. The app will automatically load and display all images

### Navigation

- **Previous/Next**: Use the arrow buttons in the toolbar
- **Jump to Image**: Click on any thumbnail in the sidebar
- **Zoom**: Pinch or scroll to zoom in/out
- **Pan**: Drag the image to move around when zoomed
- **Reset Zoom**: Double-click on the image

### Slideshow

1. Click the "Start Slideshow" button (play icon) in the toolbar
2. Images will automatically cycle at the configured interval
3. Click "Stop Slideshow" (pause icon) to stop the slideshow
4. Adjust the interval in Settings (1-10 seconds)

### Sorting

1. Click the "Sort" button in the toolbar
2. Choose from:
   - **Name**: Alphabetical order
   - **Creation Date**: Oldest to newest
   - **Custom Order**: Opens a drag-and-drop editor to arrange images manually

### Settings

1. Click the "Settings" button (gear icon) in the toolbar
2. Adjust:
   - Slideshow interval (1-10 seconds)
   - Default sort order

## Architecture

The application follows a clean SwiftUI architecture:

- **Sources/ImageBrowser/ImageBrowserApp.swift**: Main app entry point
- **Sources/ImageBrowser/AppState.swift**: Manages application state, image loading, sorting, and slideshow logic
- **Sources/ImageBrowser/ContentView.swift**: Main UI with sidebar, image viewer, and settings panels
- **Sources/ImageBrowser/FolderPicking.swift**: Folder picker UI boundary (`NSOpenPanel`)

## File Structure

```
ImageBrowser/
├── Sources/
│   └── ImageBrowser/
│       ├── ImageBrowserApp.swift  # App entry point
│       ├── AppState.swift         # State management and business logic
│       ├── ContentView.swift      # UI components and views
│       ├── FolderPicking.swift    # Folder picker helper
│       ├── AppDependencies.swift  # Dependency protocols and test doubles
│       ├── Info.plist             # App configuration
│       └── Assets.xcassets        # App icons/assets
├── Tests/
│   └── ImageBrowserTests/
├── build.sh                 # Build script for creating .app bundle
├── project.yml              # XcodeGen project spec
├── Package.swift            # Swift Package Manager configuration
├── README.md               # This file
└── ImageBrowser.app/       # Compiled app bundle (after running build.sh)
    └── Contents/
        ├── Info.plist
        ├── MacOS/
        │   └── ImageBrowser
        └── Resources/
```

## Build Script Details

The [`build.sh`](build.sh) script creates a proper macOS application bundle that can be launched by double-clicking:

- Regenerates `ImageBrowser.xcodeproj` via XcodeGen
- Builds a universal binary for Intel and Apple Silicon (`x86_64` + `arm64`)
- Copies the app bundle using `ditto --norsrc` to avoid metadata/signing issues
- Cleans extended attributes before signing
- Supports two signing modes:
  - ad-hoc signing (default)
  - Developer ID signing via `SIGN_IDENTITY`
- Verifies code signing and confirms universal architecture
- Runs Gatekeeper assessment in Developer ID mode

## Privacy

The app requires file system access to:
- Desktop folder
- Documents folder
- Downloads folder

These permissions are necessary to browse images stored on your Mac. All file access is handled locally; no data is transmitted or stored externally.

## Troubleshooting

### Build Issues

If you encounter build errors, ensure:
- You have Xcode Command Line Tools installed: `xcode-select --install`
- Swift 5.9 or later is installed: `swift --version`
- macOS 13.0 or later is installed
- XcodeGen is installed (build script can install it via Homebrew)

If `./build.sh` fails, inspect `.build/xcodebuild.log` for full compiler/build output.

### Runtime Issues

If the app doesn't launch:
- Check that macOS version is 13.0 or later
- If signed ad-hoc, launch locally (`open ImageBrowser.app`) or right-click > Open the first time
- For broad distribution, use Developer ID signing and notarization
- Check Console.app for error messages

## License

Copyright © 2025. All rights reserved.
