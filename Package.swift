// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SmartTextKey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SmartTextKey",
            targets: ["SmartTextKey"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0")
    ],
    targets: [
        .executableTarget(
            name: "SmartTextKey",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "SmartTextKeyTests",
            dependencies: ["SmartTextKey"]
        ),
    ]
)
