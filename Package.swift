// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsagePill",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeUsagePill", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
