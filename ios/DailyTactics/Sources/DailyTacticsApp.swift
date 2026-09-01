import SwiftUI
import PuzzleKit
import TacticsData

@main
struct DailyTacticsApp: App {
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
    }
}

private struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    /// First-launch gate: the puzzle library is bulk-imported into SwiftData
    /// once. Observed via `@AppStorage` so completing the import re-routes.
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    // Resolve the initial mode once per app session. The batch window changes
    // when a new batch starts, and must not cause SwiftUI to recreate the
    // active TacticsView in review mode.
    @State private var initialMode: TacticsMode?

    var body: some View {
        if !libraryImported {
            LibraryLoadingView()
        } else if let initialMode {
            TacticsView(mode: initialMode)
        } else {
            ProgressView("Loading…")
                .task {
                    dependencies.batch.restore()
                    initialMode = dependencies.batch.isWithinWindow && !dependencies.batch.activePuzzleIDs().isEmpty
                        ? .reviewBatch
                        : .play
                }
        }
    }
}
