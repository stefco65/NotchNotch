// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchNook",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchNook", targets: ["NotchNook"]),
        .executable(name: "agentbridge", targets: ["agentbridge"])
    ],
    targets: [
        .executableTarget(
            name: "NotchNook",
            path: "NotchApp",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "agentbridge",
            path: "Tools/agentbridge"
        ),
        .testTarget(
            name: "NotchAppTests",
            dependencies: ["NotchNook"],
            path: "Tests/NotchAppTests"
        )
    ]
)
