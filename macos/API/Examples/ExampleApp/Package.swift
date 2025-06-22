// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "ExampleApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Import the local AudioCaptureKit package
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ExampleApp",
            dependencies: [
                .product(name: "AudioCaptureKit", package: "AudioCaptureKit")
            ],
            path: "."
        )
    ]
)