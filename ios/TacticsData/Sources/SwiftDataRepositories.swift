import Foundation
import PuzzleKit
import SwiftData

/// The app's SwiftData container. Created once per process; owned by the
/// composition root inside TacticsData so no other module imports SwiftData.
@MainActor
public enum ModelContainerFactory {
    public static func makeShared() -> ModelContainer {
        let schema = Schema([
            PuzzleRecord.self,
            PuzzleProgress.self,
            RoundHistory.self,
            RatingSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Module-qualified model names changed when the models moved into
            // this framework; a store from the pre-framework build cannot load.
            // The app is unreleased, so the correct recovery is a clean rebuild
            // of the store plus a re-import (the first-launch gate reset).
            destroyStore()
            UserDefaults.standard.set(false, forKey: AppPreferences.libraryImported)
            if let retry = try? ModelContainer(for: schema, configurations: [config]) {
                return retry
            }
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }

    public static func makeInMemory() -> ModelContainer {
        let schema = Schema([
            PuzzleRecord.self,
            PuzzleProgress.self,
            RoundHistory.self,
            RatingSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Best-effort removal of the on-disk store backing `makeShared`.
    private static func destroyStore() {
        let url = ModelConfiguration(schema: Schema([
            PuzzleRecord.self, PuzzleProgress.self, RoundHistory.self, RatingSnapshot.self,
        ])).url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}

/// One adapter over one `ModelContext` implementing all four data ports.
/// Preserves the cached-library behavior (the ~10k-row fetch runs once per
/// store lifetime instead of per round). Bulk import is `PuzzleLibraryImporter`'s
/// job; this type exposes its context for the importer to share.
@MainActor
public final class SwiftDataRepositories: PuzzleDataRepositories {
    /// Shared with `PuzzleLibraryImporter` so both write one store.
    public let context: ModelContext

    /// The imported puzzle library is static for a session — `PuzzleRecord`
    /// rows only change on first-launch import or a full reset, both of which
    /// re-route to a fresh screen (and a fresh store). So the library is
    /// fetched once and cached.
    private var cachedLibrary: [Puzzle]?

    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    public convenience init(inMemory: Bool = false) {
        self.init(container: inMemory ? ModelContainerFactory.makeInMemory() : ModelContainerFactory.makeShared())
    }

    // MARK: - PuzzleLibraryRepository

    public func allPuzzles() -> [Puzzle] {
        if let cachedLibrary { return cachedLibrary }
        let all = ((try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []).map(\.puzzle)
        cachedLibrary = all
        return all
    }

    public func attemptedIDs() -> Set<String> {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.isAttempted == true }
        )
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.puzzleId))
    }

    /// Drops the cached library so newly inserted rows become visible.
    public func invalidateLibraryCache() {
        cachedLibrary = nil
    }

    /// Deletes every row — downloaded chunks, progress, round history, and
    /// rating snapshots. Safe while the container is live (unlike destroying
    /// the store file); the bundled chunk is re-imported by the first-launch
    /// gate afterwards.
    public func deleteAllData() {
        try? context.delete(model: PuzzleRecord.self)
        try? context.delete(model: PuzzleProgress.self)
        try? context.delete(model: RoundHistory.self)
        try? context.delete(model: RatingSnapshot.self)
        try? context.save()
        invalidateLibraryCache()
    }

    // MARK: - PuzzleProgressRepository

    public func markCompleted(_ puzzleId: String) {
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

    public func markAttempted(_ puzzleId: String) {
        markAttempted([puzzleId])
    }

    public func markAttempted(_ puzzleIds: [String]) {
        guard !puzzleIds.isEmpty else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<PuzzleProgress>())) ?? []).map(\.puzzleId))
        for id in puzzleIds where !existing.contains(id) {
            let progress = PuzzleProgress(puzzleId: id)
            progress.isAttempted = true
            context.insert(progress)
        }
        try? context.save()
    }

    public func hasAttempted(_ puzzleId: String) -> Bool {
        let descriptor = FetchDescriptor<PuzzleProgress>(predicate: #Predicate { $0.puzzleId == puzzleId })
        return (try? context.fetch(descriptor).first?.isAttempted) ?? false
    }

    public func isCompleted(_ puzzleId: String) -> Bool {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.puzzleId == puzzleId }
        )
        return (try? context.fetch(descriptor).first?.isCompleted) ?? false
    }

    public func markFailed(_ puzzleId: String) {
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

    public func failedCount() -> Int {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.hasFailed == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    public func completedCount() -> Int {
        let descriptor = FetchDescriptor<PuzzleProgress>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - RoundHistoryRepository

    public func recordRound(puzzles: [Puzzle], outcomes: [PuzzleOutcome?]) {
        let encoded = outcomes.map { outcome in
            switch outcome {
            case .correct: return "correct"
            case .wrong: return "wrong"
            case nil: return "unknown"
            }
        }
        context.insert(RoundHistory(puzzleIDs: puzzles.map(\.id), outcomes: encoded))
        try? context.save()
    }

    public func history() -> [RoundSummary] {
        let descriptor = FetchDescriptor<RoundHistory>(sortBy: [SortDescriptor(\RoundHistory.completedAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map { round in
            RoundSummary(
                id: round.id,
                completedAt: round.completedAt,
                puzzleIDs: round.puzzleIDs,
                outcomes: round.outcomes.map { raw in
                    switch raw {
                    case "correct": return PuzzleOutcome.correct
                    case "wrong": return PuzzleOutcome.wrong
                    default: return nil
                    }
                }
            )
        }
    }

    // MARK: - RatingHistoryRepository

    public func recordRatingSnapshot(value: Int) {
        context.insert(RatingSnapshot(rating: value))
        try? context.save()
    }

    public func ratingHistory() -> [RatingSample] {
        let descriptor = FetchDescriptor<RatingSnapshot>(sortBy: [SortDescriptor(\RatingSnapshot.recordedAt)])
        return ((try? context.fetch(descriptor)) ?? []).map { snapshot in
            RatingSample(id: snapshot.id, recordedAt: snapshot.recordedAt, rating: snapshot.rating)
        }
    }
}
