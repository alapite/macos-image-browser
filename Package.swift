// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ImageBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ImageBrowser",
            targets: ["ImageBrowser"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
    ],
    targets: [
        .executableTarget(
            name: "ImageBrowser",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            exclude: [
                "Info.plist",
                "Database/README.md",
                "Models/README.md",
                "Stores/README.md"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "ImageBrowserTests",
            dependencies: ["ImageBrowser"],
            path: "Tests",
            exclude: [
                "Shell",
                "Fixtures/basic/ImageBrowserUITests.sqlite",
                "Fixtures/basic/ImageBrowserUITests.sqlite-shm",
                "Fixtures/basic/ImageBrowserUITests.sqlite-wal",
                "Fixtures/corrupted/ImageBrowserUITests.sqlite",
                "Fixtures/corrupted/ImageBrowserUITests.sqlite-shm",
                "Fixtures/corrupted/ImageBrowserUITests.sqlite-wal",
                "Fixtures/slideshow/ImageBrowserUITests.sqlite",
                "Fixtures/slideshow/ImageBrowserUITests.sqlite-shm",
                "Fixtures/slideshow/ImageBrowserUITests.sqlite-wal"
            ],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
