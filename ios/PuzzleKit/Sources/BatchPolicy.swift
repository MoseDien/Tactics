import Foundation

/// Batch cadence configuration.
public enum BatchPolicy {
    public static let puzzleCount = 5

    /// A new batch can be started after this window (see docs/BUSINESS_LOGIC.md).
    /// Debug builds use a short window so the batch cycle is testable by hand.
    public static var batchDuration: TimeInterval {
        #if DEBUG
        5 * 60
        #else
        8 * 60 * 60
        #endif
    }
}

/// A batch's time window, decoupled from any clock or storage. The tracker
/// supplies `now`; tests inject any duration.
public struct BatchWindow: Sendable, Equatable {
    public let startedAt: Date
    public let duration: TimeInterval

    public init(startedAt: Date, duration: TimeInterval = BatchPolicy.batchDuration) {
        self.startedAt = startedAt
        self.duration = duration
    }

    public var expiresAt: Date { startedAt + duration }

    /// Whether `instant` is strictly inside the window.
    public func contains(_ instant: Date) -> Bool {
        instant >= startedAt && instant < expiresAt
    }

    /// Seconds left at `now`; negative once expired.
    public func secondsRemaining(at now: Date) -> TimeInterval {
        expiresAt.timeIntervalSince(now)
    }
}

/// First-occurrence-wins id → puzzle lookup over the library. Tolerates
/// duplicated library ids (a trap risk with `Dictionary(uniqueKeysWithValues:)`).
public enum BatchLookup {
    public static func puzzles(withIDs ids: [String], in library: [Puzzle]) -> [Puzzle] {
        var lookup: [String: Puzzle] = [:]
        lookup.reserveCapacity(library.count)
        for puzzle in library where lookup[puzzle.id] == nil {
            lookup[puzzle.id] = puzzle
        }
        return ids.compactMap { lookup[$0] }
    }
}
