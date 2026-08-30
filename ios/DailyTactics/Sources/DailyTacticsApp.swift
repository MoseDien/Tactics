import SwiftUI
import SwiftData

@main
struct DailyTacticsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [PuzzleProgress.self, PuzzleRecord.self, RoundHistory.self])
    }
}

private struct RootView: View {
    /// First-launch gate: the puzzle library is bulk-imported into SwiftData
    /// once. Observed via `@AppStorage` so completing the import re-routes.
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false

    var body: some View {
        if !libraryImported {
            LibraryLoadingView()
        } else if BatchStore.isWithinDuration && !BatchStore.activePuzzleIDs.isEmpty {
            TacticsView(mode: .review)
        } else {
            TacticsView(mode: .play)
        }
    }
}
