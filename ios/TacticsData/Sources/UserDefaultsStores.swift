import Foundation
import PuzzleKit

/// Every UserDefaults key the app writes, in one place so the debug reset
/// can wipe them all and so the stores can't drift from the list.
public enum AppPreferences {
    public static let userRating = "dailytactics.userRating"
    public static let difficultyMode = "dailytactics.difficultyMode"
    public static let batchStartTime = "dailytactics.batchStartTime"
    public static let activeBatchPuzzleIDs = "dailytactics.activeBatchPuzzleIDs"
    public static let puzzleSequence = "dailytactics.puzzleSequence"
    public static let libraryImported = "dailytactics.libraryImported"
    public static let pieceAnimation = "dailytactics.pieceAnimation"

    /// All of the above.
    public static let allKeys: [String] = [
        userRating, difficultyMode, batchStartTime, activeBatchPuzzleIDs,
        puzzleSequence, libraryImported, pieceAnimation,
    ]

    /// Debug reset: removes every stored preference (rating, batch window,
    /// difficulty, chunk sequence, import gate included).
    public static func wipeAll(defaults: UserDefaults = .standard) {
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

/// The user's current rating: a single scalar persisted in UserDefaults.
/// Snapshots for the trend chart live in SwiftData (`RatingSnapshot`).
@MainActor
public final class UserRatingStore {
    private let defaults: UserDefaults
    private let key = AppPreferences.userRating
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

/// Whether pieces slide between squares (debug toggle). Absent = on, so a
/// fresh install animates and the debug reset restores the default.
@MainActor
public final class PieceAnimationStore {
    private let key = AppPreferences.pieceAnimation
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }
}

/// Difficulty setting for new batches, persisted in UserDefaults. Instances
/// (injectable defaults) — no global statics.
@MainActor
public final class DifficultyModeStore {
    private let key = AppPreferences.difficultyMode
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
    private let startKey = AppPreferences.batchStartTime
    private let puzzleIDsKey = AppPreferences.activeBatchPuzzleIDs
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
