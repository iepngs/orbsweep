// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrbSweep",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OrbSweep", targets: ["OrbSweep"])],
    targets: [
        .target(name: "CleanupCore"),
        .target(name: "UpdateCore"),
        .executableTarget(name: "OrbSweep", dependencies: ["CleanupCore", "UpdateCore"]),
        .executableTarget(name: "SafetyChecks", dependencies: ["CleanupCore", "UpdateCore"], path: "Tests/CleanupCoreTests")
    ]
)
