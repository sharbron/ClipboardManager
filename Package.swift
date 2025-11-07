// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipboardManager", targets: ["ClipboardManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        ),
        .testTarget(
            name: "ClipboardManagerTests",
            dependencies: [
                "ClipboardManager",
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        )
    ]
)
