// swift-tools-version: 6.2
// Native MilkDrop-style music visualizer (Metal + AVAudioEngine tap).
// Ported from the web app's butterchurn setup — see README in
// volspire-ui-v2/ios-visualizer-metal for the architecture write-up.

import PackageDescription

let package = Package(
    name: "Visualizer",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "Visualizer",
            targets: ["Visualizer"]
        )
    ],
    targets: [
        .target(
            name: "Visualizer",
            swiftSettings: [
                // The render loop predates strict concurrency; MTKViewDelegate +
                // NotificationCenter patterns are Swift-5-mode for now.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
