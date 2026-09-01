import Foundation
import PuzzleKit

/// The user's current rating: a single scalar persisted in UserDefaults.
/// Snapshots for the trend chart live in SwiftData (`RatingSnapshot`).
@MainActor
public final class UserRatingStore {
    private let defaults: UserDefaults
    private let key = "dailytactics.userRating"
    private let initialRating = 1500

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var rating: Int {
        let stored = defaults.integer(forKey: key)
        return stored == 0 ? initialRating : stored
    }

    public func apply(delta: Int) -> Int {
        let updated = min(3000, max(400, rating + delta))
        defaults.set(updated, forKey: key)
        return updated
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }

    public func set(rating: Int) {
        let normalized = min(3000, max(400, rating))
        defaults.set(normalized, forKey: key)
    }
}

/// Difficulty setting for new batches, persisted in UserDefaults. Instances
/// (injectable defaults) — no global statics.
@MainActor
public final class DifficultyModeStore {
    private let key = "dailytactics.difficultyMode"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var current: DifficultyMode {
        guard let raw = defaults.string(forKey: key),
              let mode = DifficultyMode(rawValue: raw) else { return .medium }
        return mode
    }

    public func set(_ mode: DifficultyMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

/// Persisted batch state: the active batch's start time and fixed puzzle ids.
@MainActor
public final class UserDefaultsBatchStateStore: BatchStateRepository {
    private let startKey = "dailytactics.batchStartTime"
    private let puzzleIDsKey = "dailytactics.activeBatchPuzzleIDs"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func startTime() -> Date? {
        defaults.object(forKey: startKey) as? Date
    }

    public func activePuzzleIDs() -> [String] {
        defaults.stringArray(forKey: puzzleIDsKey) ?? []
    }

    public func begin(_ puzzles: [Puzzle], at start: Date) {
        defaults.set(start, forKey: startKey)
        defaults.set(puzzles.map(\.id), forKey: puzzleIDsKey)
    }
}
