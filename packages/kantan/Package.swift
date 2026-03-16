// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "kantan",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
  ],
  targets: [
    .executableTarget(
      name: "kantan",
      dependencies: [.product(name: "Yams", package: "Yams")]
    ),
    .testTarget(
      name: "kantanTests",
      dependencies: ["kantan"]
    ),
  ]
)
