// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchNook",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchNook", targets: ["NotchNook"])
    ],
    targets: [
        .executableTarget(
            name: "NotchNook",
            path: "NotchApp",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "NotchAppTests",
            dependencies: ["NotchNook"],
            path: "Tests/NotchAppTests"
        )
    ]
)
