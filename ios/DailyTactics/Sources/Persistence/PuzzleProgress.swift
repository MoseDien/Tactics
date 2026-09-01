import Foundation
import PuzzleKit
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
    var isAttempted: Bool = false
    var hasFailed: Bool = false
    var completedAt: Date?

    init(puzzleId: String) {
        self.puzzleId = puzzleId
        self.isCompleted = false
        self.isAttempted = false
        self.hasFailed = false
        self.completedAt = nil
    }
}

/// Main-actor façade over the SwiftData context for recording and querying
/// puzzle completion. Kept behind a small injectable type so the storage can be
/// swapped (or made in-memory for previews/tests) without leaking SwiftData
/// through the feature layer.
@MainActor
final class PuzzleProgressStore {
    let context: ModelContext
    /// The imported puzzle library is static for a session — `PuzzleRecord` rows
    /// only change on first-launch import or a full reset, both of which
    /// re-route to a fresh screen (and a fresh store). So the library is fetched
    /// once and cached. Without this, every round re-materialized ~10k SwiftData
    /// objects, which was the per-round loading lag.
    private var cachedLibrary: [Puzzle]?

    init(context: ModelContext) {
        self.context = context
    }

    /// All puzzles in the imported library, fetched once and cached for the
    /// lifetime of this store (i.e. the Tactics screen session).
    func allPuzzles() -> [Puzzle] {
        if let cachedLibrary { return cachedLibrary }
        let all = ((try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []).map(\.puzzle)
        cachedLibrary = all
        return all
    }

    func markCompleted(_ puzzleId: String) {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.isCompleted = true
            existing.isAttempted = true
            existing.completedAt = .now
        } else {
            let progress = PuzzleProgress(puzzleId: puzzleId)
            progress.isCompleted = true
            progress.isAttempted = true
            progress.completedAt = .now
            context.insert(progress)
        }
        try? context.save()
    }

    func markAttempted(_ puzzleId: String) {
        let descriptor = FetchDescriptor<PuzzleProgress>(predicate: #Predicate { $0.puzzleId == puzzleId })
        if let existing = try? context.fetch(descriptor).first {
            existing.isAttempted = true
        } else {
            let progress = PuzzleProgress(puzzleId: puzzleId)
            progress.isAttempted = true
            context.insert(progress)
        }
        try? context.save()
    }

    func hasAttempted(_ puzzleId: String) -> Bool {
        let descriptor = FetchDescriptor<PuzzleProgress>(predicate: #Predicate { $0.puzzleId == puzzleId })
        return (try? context.fetch(descriptor).first?.isAttempted) ?? false
    }

    func isCompleted(_ puzzleId: String) -> Bool {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        return (try? context.fetch(descriptor).first?.isCompleted) ?? false
    }

    /// Record that a wrong move occurred on this puzzle (idempotent). The user may
    /// still retry — this only persists the failure for stats.
    func markFailed(_ puzzleId: String) {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.hasFailed = true
        } else {
            let progress = PuzzleProgress(puzzleId: puzzleId)
            progress.hasFailed = true
            context.insert(progress)
        }
        try? context.save()
    }

    func failedCount() -> Int {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.hasFailed == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func completedCount() -> Int {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// The round-start query: `count` random puzzles that have not been
    /// attempted yet, drawn from the cached library (no rating-band filter).
    /// Falls back to random-over-all when fewer than `count` remain unattempted
    /// so a round is always available. The static library is cached; only the
    /// small `PuzzleProgress` table is queried each round.
    func fetchUnattemptedRound(count: Int, difficulty: DifficultyMode = .medium, userRating: Int = 1500) -> [Puzzle] {
        let all = allPuzzles()
        guard !all.isEmpty else { return [] }
        let attemptedDescriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.isAttempted == true }
        )
        let attempted = Set(((try? context.fetch(attemptedDescriptor)) ?? []).map(\.puzzleId))
        let pool = all.filter { !attempted.contains($0.id) }
        let filtered: [Puzzle]
        switch difficulty {
        case .easy: filtered = pool.filter { ($0.rating ?? 0) <= userRating + 200 }
        case .hard: filtered = pool.filter { ($0.rating ?? Int.max) >= userRating - 200 }
        case .medium: filtered = pool
        }
        let source = filtered.count >= count ? filtered : (pool.count >= count ? pool : all)
        return Array(source.shuffled().prefix(min(count, source.count)))
    }
}
