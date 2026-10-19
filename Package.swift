// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "key-cli",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "key",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
            ]
        )
    ]
)
