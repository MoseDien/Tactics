import ProjectDescription

let project = Project(
    name: "DailyTactics",
    organizationName: "DailyTactics",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "4V4QEMAAYL"
        ]
    ),
    targets: [
        .target(
            name: "DailyTactics",
            destinations: .iOS,
            product: .app,
            bundleId: "com.dienbell.tactics",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "DailyTactics",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait"
                ]
            ]),
            sources: ["DailyTactics/Sources/**"],
            resources: ["DailyTactics/Resources/**"]
        ),
        .target(
            name: "DailyTacticsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.dienbell.tactics.tests",
            infoPlist: .default,
            sources: ["DailyTactics/Tests/**"],
            dependencies: [.target(name: "DailyTactics")]
        )
    ],
    schemes: [
        .scheme(
            name: "DailyTactics",
            shared: true,
            buildAction: .buildAction(targets: ["DailyTactics"]),
            testAction: .targets(["DailyTacticsTests"]),
            runAction: .runAction(configuration: .debug)
        )
    ]
)
