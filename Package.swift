// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "deployBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "deployBar",
            targets: ["deployBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "deployBar",
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
            name: "deployBarTests",
            dependencies: ["deployBar"]
        ),
    ]
)
