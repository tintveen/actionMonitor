// swift-tools-version: 6.2
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
            name: "deployBar"
        ),
        .testTarget(
            name: "deployBarTests",
            dependencies: ["deployBar"]
        ),
    ]
)
