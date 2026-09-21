// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VibeStatistics",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "VibeStatistics", targets: ["VibeStatistics"])],
    targets: [
        .executableTarget(name: "VibeStatistics", resources: [.copy("Resources/AgentLogos"), .copy("Resources/MingCute"), .copy("Resources/StatusTags"), .copy("Resources/Nico")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "VibeStatisticsTests", dependencies: ["VibeStatistics"], path: "Tests/Swift")
    ]
)
