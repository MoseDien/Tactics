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
    @Query private var puzzleRecords: [PuzzleRecord]
    @State private var puzzles = RatingAssessmentLoader.loadBundled()

    var body: some View {
        if assessments.contains(where: { $0.isCompleted }) {
            let rating = UserRatingStore().rating
            let level = RatingLevel(rating: rating)
            let scopedPuzzles = puzzleRecords
                .filter { level.ratingRange.contains($0.rating) }
                .map(\.puzzle)
            TacticsView(dataset: scopedPuzzles, dailyPuzzleCount: 5)
        } else {
            RatingAssessmentView(puzzles: RatingAssessmentPlan.make(from: puzzles, count: assessmentPuzzleCount).puzzles)
        }
    }
}
