// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spindle",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "spindle", targets: ["Spindle"])
    ],
    targets: [
        .executableTarget(
            name: "Spindle",
            path: "Sources/Spindle"
        )
    ]
)
