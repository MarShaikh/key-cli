// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "key-cli",
    platforms: [.macOS(.v13)],
    targets: [
        // Code with no side effects, kept apart so the tests can import it.
        .target(name: "KeyCore"),
        .executableTarget(
            name: "key",
            dependencies: ["KeyCore"],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
        .testTarget(name: "KeyCoreTests", dependencies: ["KeyCore"]),
    ]
)
