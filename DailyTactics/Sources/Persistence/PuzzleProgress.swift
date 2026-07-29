import Foundation
import SwiftData

/// Persisted completion state for a single puzzle, keyed by its Lichess id.
///
/// This is the "user has already done it" field: it is user/runtime state and is
/// kept separate from the static puzzle content (`Puzzle`), so the bundled data
/// stays read-only.
@Model
final class PuzzleProgress {
    var puzzleId: String
    var isCompleted: Bool
    var completedAt: Date?

    init(puzzleId: String) {
        self.puzzleId = puzzleId
        self.isCompleted = false
        self.completedAt = nil
    }
}

/// Main-actor façade over the SwiftData context for recording and querying
/// puzzle completion. Kept behind a small injectable type so the storage can be
/// swapped (or made in-memory for previews/tests) without leaking SwiftData
/// through the feature layer.
@MainActor
struct PuzzleProgressStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func markCompleted(_ puzzleId: String) {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.isCompleted = true
            existing.completedAt = .now
        } else {
            let progress = PuzzleProgress(puzzleId: puzzleId)
            progress.isCompleted = true
            progress.completedAt = .now
            context.insert(progress)
        }
        try? context.save()
    }

    func isCompleted(_ puzzleId: String) -> Bool {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        return (try? context.fetch(descriptor).first?.isCompleted) ?? false
    }

    func completedCount() -> Int {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
