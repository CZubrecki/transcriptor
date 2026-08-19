// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "transcriptor",
  platforms: [.macOS("26.0")],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
  ],
  targets: [
    .target(name: "TranscriptorKit"),
    .executableTarget(
      name: "transcriptor",
      dependencies: [
        "TranscriptorKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(name: "TranscriptorKitTests", dependencies: ["TranscriptorKit"]),
  ]
)
