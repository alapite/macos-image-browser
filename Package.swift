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
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "ImageBrowserTests",
            dependencies: ["ImageBrowser"],
            path: "Tests",
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
