// swift-tools-version: 5.7
  import PackageDescription

  let package = Package(
      name: "AudioCaptureLibrary",
      platforms: [
          .macOS(.v13)
      ],
      products: [
          .library(
              name: "AudioCaptureKit",
              targets: ["AudioCaptureKit"]
          ),
      ],
      targets: [
          .target(
              name: "AudioCaptureKit",
              path: "macos/API/Sources/AudioCaptureKit"
          ),
      ]
  )