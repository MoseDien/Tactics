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
    // Built once per session so window changes and Home↔board navigation
    // never recreate the training store.
    @State private var screen: TacticsScreenViewModel?
    #if DEBUG
    // Smoke-test payload: `simctl launch ... -showAnalysisBoard 1`.
    @State private var smokeAnalysisSeed: AnalysisSeed?
    #endif

    var body: some View {
        Group {
            if !libraryImported {
                LibraryLoadingView()
            } else if let screen {
                HomeView()
                    .environment(screen)
            } else {
                ProgressView("Loading…")
                    .task { await buildSession() }
            }
        }
        #if DEBUG
        .sheet(item: $smokeAnalysisSeed) { seed in
            NavigationStack {
                AnalysisScreenView(
                    seedFEN: seed.fen,
                    openingMove: seed.openingMove,
                    startsFlipped: seed.startsFlipped
                )
            }
            .presentationDetents([.large])
        }
        #endif
    }

    /// Resolve the persisted round, then build the session-scoped training
    /// store that Home and the board share. `screen` is set last: it swaps
    /// the branch and detaches this task's host.
    @MainActor
    private func buildSession() async {
        dependencies.round.restore()
        let configuration = TacticsLaunchConfiguration.resolve(
            activePuzzleIDs: dependencies.round.activePuzzleIDs(),
            nextPuzzleIndex: dependencies.round.nextPuzzleIndex(),
            storedMode: dependencies.round.roundMode()
        )
        _ = await dependencies.provisioner.ensureRoundAvailable(minimum: RoundPolicy.puzzleCount)
        let training = TacticsTrainingStore(
            dependencies: dependencies,
            dailyPuzzleCount: RoundPolicy.puzzleCount,
            mode: configuration.mode,
            resumesActiveRound: configuration.resumesActiveRound
        )
        let built = TacticsScreenViewModel(training: training)
        built.start()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "showAnalysisBoard") {
            smokeAnalysisSeed = AnalysisSeed(
                puzzle: training.roundState.puzzles[training.roundState.currentIndex],
                startsFlipped: training.sessionState.isBoardFlipped
            )
        }
        #endif
        screen = built
    }
}
