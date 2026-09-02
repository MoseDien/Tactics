import Foundation

// Domain values exchanged across the repository seams. Property names mirror
// the SwiftData models so views move over with minimal churn.

/// One completed batch in the history list.
public struct RoundSummary: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let completedAt: Date
    public let puzzleIDs: [String]
    public let outcomes: [PuzzleOutcome?]

    public init(id: UUID, completedAt: Date, puzzleIDs: [String], outcomes: [PuzzleOutcome?]) {
        self.id = id
        self.completedAt = completedAt
        self.puzzleIDs = puzzleIDs
        self.outcomes = outcomes
    }
}

/// One rating sample — the settled rating after a completed batch.
public struct RatingSample: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordedAt: Date
    public let rating: Int

    public init(id: UUID, recordedAt: Date, rating: Int) {
        self.id = id
        self.recordedAt = recordedAt
        self.rating = rating
    }
}

// MARK: - Ports

/// Read side of the imported library plus the attempted set. Backed by
/// SwiftData today; a remote-backed cache satisfies the same contract later.
@MainActor
public protocol PuzzleLibraryRepository: AnyObject {
    /// The imported library, cached for the session. Empty before first import.
    func allPuzzles() -> [Puzzle]
    /// IDs the user has already attempted — drives unattempted-first selection.
    func attemptedIDs() -> Set<String>
}

/// Per-puzzle runtime progress.
@MainActor
public protocol PuzzleProgressRepository: AnyObject {
    func markCompleted(_ puzzleId: String)
    func markAttempted(_ puzzleId: String)
    func markFailed(_ puzzleId: String)
    func hasAttempted(_ puzzleId: String) -> Bool
    func isCompleted(_ puzzleId: String) -> Bool
    func completedCount() -> Int
    func failedCount() -> Int
}

/// One row per completed batch.
@MainActor
public protocol RoundHistoryRepository: AnyObject {
    func recordRound(puzzles: [Puzzle], outcomes: [PuzzleOutcome?])
    func history() -> [RoundSummary]
}

/// One rating sample per completed batch.
@MainActor
public protocol RatingHistoryRepository: AnyObject {
    func recordRatingSnapshot(value: Int)
    /// All samples oldest-first, ready for a trend chart.
    func ratingHistory() -> [RatingSample]
}

/// Umbrella over the four data ports: one adapter object, one test fake.
@MainActor
public protocol PuzzleDataRepositories: PuzzleLibraryRepository,
    PuzzleProgressRepository, RoundHistoryRepository, RatingHistoryRepository {}

/// Persisted batch state (active batch identity + start time).
@MainActor
public protocol BatchStateRepository: AnyObject {
    func startTime() -> Date?
    func activePuzzleIDs() -> [String]
    func begin(_ puzzles: [Puzzle], at start: Date)
}

/// First-launch bulk import of the bundled library.
@MainActor
public protocol LibraryImporting: AnyObject {
    /// Returns the number of tiers that failed to decode (0 = success).
    func importAllBundled(progress: @escaping @Sendable (Double) -> Void) async -> Int
}

// MARK: - Chunked delivery

/// Fetches one remote puzzle chunk. `nil` means the chunk does not exist yet
/// (HTTP 404) — the caller stops asking for higher sequences this session.
@MainActor
public protocol PuzzleChunkFetching: AnyObject {
    func fetchChunk(_ sequence: Int) async throws -> [Puzzle]?
}

/// Keeps the local library stocked: when fewer than `minimum` unattempted
/// puzzles remain, the next chunk is fetched and imported. Failures are
/// swallowed (offline, timeout, bad data) — the existing selection fallbacks
/// still guarantee a playable batch.
@MainActor
public protocol PuzzleProvisioning: AnyObject {
    /// Returns how many new puzzles were imported (0 when none were needed
    /// or the fetch failed).
    func ensureBatchAvailable(minimum: Int) async -> Int
}
