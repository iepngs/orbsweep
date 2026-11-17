// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrbSweep",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OrbSweep", targets: ["OrbSweep"])],
    targets: [
        .target(name: "CleanupCore"),
        .executableTarget(name: "OrbSweep", dependencies: ["CleanupCore"]),
        .executableTarget(name: "SafetyChecks", dependencies: ["CleanupCore"], path: "Tests/CleanupCoreTests")
    ]
)
