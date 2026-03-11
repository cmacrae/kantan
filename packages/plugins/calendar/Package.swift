// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "kantan-plugin-calendar",
  platforms: [
    .macOS(.v15)
  ],
  targets: [
    .executableTarget(
      name: "kantan-plugin-calendar",
      linkerSettings: [
        .linkedFramework("EventKit")
      ]
    )
  ]
)
