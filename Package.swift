// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DialkitmacOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DialkitmacOS",
            targets: ["DialkitmacOS"]
        ),
        .library(
            name: "DialkitmacOSInAppUI",
            targets: ["DialkitmacOSInAppUI"]
        ),
        .library(
            name: "DialkitmacOSAgent",
            targets: ["DialkitmacOSAgent"]
        ),
        .library(
            name: "DialkitmacOSCore",
            targets: ["DialkitmacOSCore"]
        ),
        .library(
            name: "DialkitmacOSProtocol",
            targets: ["DialkitmacOSProtocol"]
        ),
        .executable(
            name: "dialkit-macos",
            targets: ["DialkitmacOSApp"]
        ),
        .executable(
            name: "dialkit",
            targets: ["DialkitmacOSCLI"]
        )
    ],
    targets: [
        .target(
            name: "DialkitmacOSProtocol",
            path: "Sources/DialKitProtocol"
        ),
        .target(
            name: "DialkitmacOSCore",
            dependencies: ["DialkitmacOSProtocol"],
            path: "Sources/DialKitCore"
        ),
        .target(
            name: "DialkitmacOS",
            dependencies: ["DialkitmacOSCore"],
            path: "Sources/DialKit"
        ),
        .target(
            name: "DialkitmacOSInAppUI",
            dependencies: ["DialkitmacOS"],
            path: "Sources/DialKitInAppUI"
        ),
        .target(
            name: "DialkitmacOSAgent",
            dependencies: ["DialkitmacOSCore", "DialkitmacOSProtocol"],
            path: "Sources/DialKitAgent"
        ),
        .executableTarget(
            name: "DialkitmacOSApp",
            dependencies: ["DialkitmacOSProtocol"],
            path: "Sources/DialKitMacOSApp"
        ),
        .executableTarget(
            name: "DialkitmacOSCLI",
            path: "Sources/DialKitCLI"
        ),
        .testTarget(
            name: "DialkitmacOSProtocolTests",
            dependencies: ["DialkitmacOSProtocol"],
            path: "Tests/DialKitProtocolTests"
        ),
        .testTarget(
            name: "DialkitmacOSCoreTests",
            dependencies: ["DialkitmacOSCore"],
            path: "Tests/DialKitCoreTests"
        ),
        .testTarget(
            name: "DialkitmacOSInAppUITests",
            dependencies: ["DialkitmacOSInAppUI"],
            path: "Tests/DialKitInAppUITests"
        )
    ]
)
