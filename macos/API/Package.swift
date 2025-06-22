// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AudioCaptureKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AudioCaptureKit",
            targets: ["AudioCaptureKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // No external dependencies - using only system frameworks
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AudioCaptureKit",
            dependencies: [],
            path: "Sources/AudioCaptureKit",
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "AudioCaptureKitTests",
            dependencies: ["AudioCaptureKit"],
            path: "Tests/AudioCaptureKitTests"
        ),
    ]
)