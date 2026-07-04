// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CCUsageTaskbar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CCUsageTaskbar", targets: ["CCUsageTaskbar"])
    ],
    targets: [
        .executableTarget(
            name: "CCUsageTaskbar",
            path: "Sources/CCUsageTaskbar"
        )
    ]
)
