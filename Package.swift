// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenLaunchpad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenLaunchpad",
            targets: ["OpenLaunchpad"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenLaunchpad",
            path: "Sources/OpenLaunchpad"
        )
    ]
)
