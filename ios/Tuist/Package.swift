// swift-tools-version: 6.0
import PackageDescription

/// External dependencies, installed with `tuist install` and referenced from
/// Project.swift via `.external(name:)`. TCA lives in the app target only.
let package = Package(
    name: "DailyTactics",
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.26.2"
        ),
        // Declared explicitly so its products (.Dependencies /
        // DependenciesMacros) can be linked directly by the app target.
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.4.0"
        ),
    ]
)
