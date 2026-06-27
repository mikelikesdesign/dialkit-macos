// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DialKitMacOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DialKit",
            targets: ["DialKit"]
        ),
        .library(
            name: "DialKitAgent",
            targets: ["DialKitAgent"]
        ),
        .library(
            name: "DialKitCore",
            targets: ["DialKitCore"]
        ),
        .library(
            name: "DialKitProtocol",
            targets: ["DialKitProtocol"]
        ),
        .executable(
            name: "dialkit-macos",
            targets: ["DialKitMacOSApp"]
        ),
        .executable(
            name: "dialkit",
            targets: ["DialKitCLI"]
        )
    ],
    targets: [
        .target(
            name: "DialKitProtocol"
        ),
        .target(
            name: "DialKitCore",
            dependencies: ["DialKitProtocol"]
        ),
        .target(
            name: "DialKit",
            dependencies: ["DialKitCore"]
        ),
        .target(
            name: "DialKitAgent",
            dependencies: ["DialKitCore", "DialKitProtocol"]
        ),
        .executableTarget(
            name: "DialKitMacOSApp",
            dependencies: ["DialKitProtocol"]
        ),
        .executableTarget(
            name: "DialKitCLI"
        ),
        .testTarget(
            name: "DialKitProtocolTests",
            dependencies: ["DialKitProtocol"]
        ),
        .testTarget(
            name: "DialKitCoreTests",
            dependencies: ["DialKitCore"]
        ),
        .testTarget(
            name: "DialKitTests",
            dependencies: ["DialKit"]
        )
    ]
)
