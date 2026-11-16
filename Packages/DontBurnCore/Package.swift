// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DontBurnCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "DontBurnCore", targets: ["DontBurnCore"]),
    ],
    targets: [
        .target(
            name: "DontBurnCore",
            swiftSettings: [.treatAllWarnings(as: .error)],
        ),
        .testTarget(
            name: "DontBurnCoreTests",
            dependencies: ["DontBurnCore"],
            swiftSettings: [.treatAllWarnings(as: .error)],
        ),
    ],
)
