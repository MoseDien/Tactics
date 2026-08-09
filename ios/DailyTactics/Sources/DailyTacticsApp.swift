import SwiftUI
import SwiftData

@main
struct DailyTacticsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [PuzzleProgress.self, RatingAssessment.self, PuzzleRecord.self])
    }
}

private struct RootView: View {
    private let assessmentPuzzleCount = 4
    @Query private var assessments: [RatingAssessment]
    /// First-launch gate: the puzzle library is bulk-imported into SwiftData
    /// once. Observed via `@AppStorage` so completing the import re-routes.
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    @State private var assessmentPuzzles = RatingAssessmentLoader.loadBundled()

    var body: some View {
        if !libraryImported {
            LibraryLoadingView()
        } else if assessments.contains(where: { $0.isCompleted }) {
            // Rounds are queried from SwiftData at each round boundary inside
            // TacticsView, so no dataset is pre-built here.
            TacticsView()
        } else {
            RatingAssessmentView(puzzles: RatingAssessmentPlan.make(from: assessmentPuzzles, count: assessmentPuzzleCount).puzzles)
        }
    }
}
