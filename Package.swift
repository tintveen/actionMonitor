// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "actionMonitor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "actionMonitor",
            targets: ["actionMonitor"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "actionMonitor",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                // Embed app metadata so AppKit can resolve Bundle.main.bundleIdentifier.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "actionMonitorTests",
            dependencies: ["actionMonitor"]
        ),
    ]
)
