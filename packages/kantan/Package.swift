// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "kantan",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/behrang/YamlSwift.git", from: "3.4.4")
    ],
    targets: [
        .executableTarget(
            name: "kantan",
            dependencies: [.product(name: "Yaml", package: "YamlSwift")]
        ),
        .testTarget(
            name: "kantanTests",
            dependencies: ["kantan"]
        ),
    ]
)
