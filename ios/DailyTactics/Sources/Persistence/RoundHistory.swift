import Foundation
import SwiftData

@Model
final class RoundHistory {
    var id: UUID
    var completedAt: Date
    var puzzleIDs: [String]
    var outcomes: [String]

    init(puzzleIDs: [String], outcomes: [PuzzleOutcome?]) {
        self.id = UUID()
        self.completedAt = .now
        self.puzzleIDs = puzzleIDs
        self.outcomes = outcomes.map { outcome in
            switch outcome {
            case .correct: return "correct"
            case .wrong: return "wrong"
            case nil: return "unknown"
            }
        }
    }
}

@MainActor
extension PuzzleProgressStore {
    func recordRound(puzzles: [Puzzle], outcomes: [PuzzleOutcome?]) {
        context.insert(RoundHistory(puzzleIDs: puzzles.map(\.id), outcomes: outcomes))
        try? context.save()
    }

    func history() -> [RoundHistory] {
        let descriptor = FetchDescriptor<RoundHistory>(sortBy: [SortDescriptor(\RoundHistory.completedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
