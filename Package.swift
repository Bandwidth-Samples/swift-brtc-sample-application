// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "brtc-swift-sample-application",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "brtc-swift-sample-application",
            targets: ["brtc-swift-sample-application"]
        )
    ],
    dependencies: [
        .package(name: "BandwidthWebRTC", path: "../in-app-calling-swift-sdk")
    ],
    targets: [
        .executableTarget(
            name: "brtc-swift-sample-application",
            dependencies: [
                .product(name: "BandwidthWebRTC", package: "BandwidthWebRTC")
            ],
            path: "Sources/brtc-swift-sample-application"
        )
    ]
)
