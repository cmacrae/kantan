// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "kantan-plugin-reminders",
  platforms: [
    .macOS(.v15)
  ],
  targets: [
    .executableTarget(
      name: "kantan-plugin-reminders",
      linkerSettings: [
        .linkedFramework("EventKit")
      ]
    ),
    .testTarget(
      name: "kantan-plugin-remindersTests",
      dependencies: ["kantan-plugin-reminders"]
    ),
  ]
)
