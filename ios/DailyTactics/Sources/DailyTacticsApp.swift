import SwiftUI
import PuzzleKit
import TacticsData

@main
struct DailyTacticsApp: App {
    @State private var dependencies = AppDependencies.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        dependencies.round.refresh()
                    }
                }
        }
    }
}

private struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    // Resolved once per session so window changes don't recreate TacticsView.
    @State private var launchConfiguration: TacticsLaunchConfiguration?

    var body: some View {
        if !libraryImported {
            LibraryLoadingView()
        } else if let launchConfiguration {
            TacticsView(
                mode: launchConfiguration.mode,
                resumesActiveRound: launchConfiguration.resumesActiveRound
            )
        } else {
            ProgressView("Loading…")
                .task {
                    dependencies.round.restore()
                    launchConfiguration = TacticsLaunchConfiguration.resolve(
                        activePuzzleIDs: dependencies.round.activePuzzleIDs(),
                        isWithinWindow: dependencies.round.isWithinWindow
                    )
                }
        }
    }
}
