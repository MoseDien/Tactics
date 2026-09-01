import ProjectDescription

let project = Project(
    name: "DailyTactics",
    organizationName: "DailyTactics",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "4V4QEMAAYL",
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1"
        ]
    ),
    targets: [
        .target(
            name: "TacticsData",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.dienbell.tactics.tacticsdata",
            infoPlist: .default,
            sources: ["TacticsData/Sources/**"],
            resources: ["TacticsData/Resources/**"],
            dependencies: [.target(name: "PuzzleKit")]
        ),
        .target(
            name: "PuzzleKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.dienbell.tactics.puzzlekit",
            infoPlist: .default,
            sources: ["PuzzleKit/Sources/**"],
            dependencies: [.target(name: "ChessCore")]
        ),
        .target(
            name: "ChessCore",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.dienbell.tactics.chesscore",
            infoPlist: .default,
            sources: ["ChessCore/Sources/**"]
        ),
        .target(
            name: "DailyTactics",
            destinations: .iOS,
            product: .app,
            bundleId: "com.dienbell.tactics",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "iTactics",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait"
                ]
            ]),
            sources: ["DailyTactics/Sources/**"],
            resources: ["DailyTactics/Resources/**"],
            dependencies: [.target(name: "ChessCore"), .target(name: "PuzzleKit"), .target(name: "TacticsData")]
        ),
        .target(
            name: "DailyTacticsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.dienbell.tactics.tests",
            infoPlist: .default,
            sources: ["DailyTactics/Tests/**"],
            dependencies: [.target(name: "DailyTactics"), .target(name: "PuzzleKit"), .target(name: "TacticsData")]
        ),
        .target(
            name: "TacticsDataTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.dienbell.tactics.tacticsdata.tests",
            infoPlist: .default,
            sources: ["TacticsData/Tests/**"],
            dependencies: [.target(name: "TacticsData")]
        ),
        .target(
            name: "PuzzleKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.dienbell.tactics.puzzlekit.tests",
            infoPlist: .default,
            sources: ["PuzzleKit/Tests/**"],
            dependencies: [.target(name: "PuzzleKit")]
        ),
        .target(
            name: "ChessCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.dienbell.tactics.chesscore.tests",
            infoPlist: .default,
            sources: ["ChessCore/Tests/**"],
            dependencies: [.target(name: "ChessCore")]
        )
    ],
    schemes: [
        .scheme(
            name: "DailyTactics",
            shared: true,
            buildAction: .buildAction(targets: ["DailyTactics"]),
            testAction: .targets(["DailyTacticsTests", "ChessCoreTests", "PuzzleKitTests", "TacticsDataTests"]),
            runAction: .runAction(configuration: .debug)
        )
    ]
)
