// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ImageBrowser",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ImageBrowser",
            targets: ["ImageBrowser"]
        ),
    ],
    dependencies: [
        // Add any external dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "ImageBrowser",
            dependencies: [],
            path: ".",
            exclude: [
                "README.md",
                "Package.swift",
                "Info.plist",
                "build.sh",
                "project.yml",
                "ImageBrowser.xcodeproj",
                ".build",
                ".planning",
                "Tests",
                "AGENTS.md",
                "LICENSE"
            ],
            sources: [
                "ImageBrowserApp.swift",
                "AppState.swift",
                "ContentView.swift",
                "Logging.swift"
            ],
            resources: [
                .process("Info.plist")
            ]
        ),
        .testTarget(
            name: "ImageBrowserTests",
            dependencies: [
                "ImageBrowser"
            ],
            path: "Tests/ImageBrowserTests"
        ),
    ]
)
