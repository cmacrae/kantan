// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "kantan-plugin-system-monitor",
  platforms: [
    .macOS(.v15)
  ],
  targets: [
    .executableTarget(
      name: "kantan-plugin-system-monitor"
    ),
    .testTarget(
      name: "kantan-plugin-system-monitorTests",
      dependencies: ["kantan-plugin-system-monitor"]
    ),
  ]
)
