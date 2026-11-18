// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "kantan-plugin-now-playing",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "kantan-plugin-now-playing", targets: ["kantan-plugin-now-playing"]),
    .library(name: "KantanNowPlayingHost", type: .dynamic, targets: ["KantanNowPlayingHost"]),
  ],
  targets: [
    .executableTarget(
      name: "kantan-plugin-now-playing",
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .target(name: "KantanNowPlayingHost"),
    .testTarget(
      name: "kantan-plugin-now-playingTests",
      dependencies: ["kantan-plugin-now-playing"]
    ),
  ]
)
