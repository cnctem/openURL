// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "openURL",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        .executable(
            name: "openURL",
            targets: ["openURL"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "openURL",
            dependencies: [],
            path: ".",
            sources: ["main.swift"]
        )
    ]
)