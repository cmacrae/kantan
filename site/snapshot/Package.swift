// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "kantan-site-snapshot",
  platforms: [.macOS(.v15)],
  targets: [
    .executableTarget(name: "kantan-site-snapshot")
  ]
)
