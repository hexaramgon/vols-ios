// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Player",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "Player",
            targets: ["Player"]
        )
    ],
    dependencies: [
        .package(path: "../MediaLibrary/"),
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),
    ],
    targets: [
        .target(
            name: "Player",
            dependencies: [
                "MediaLibrary",
                .product(name: "AudioKit", package: "AudioKit"),
            ]
        )
    ]
)
