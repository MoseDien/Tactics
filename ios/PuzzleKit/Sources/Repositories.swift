import Foundation

// Domain values exchanged across the repository seams. Property names mirror
// the SwiftData models so views move over with minimal churn.

/// One completed round in the history list.
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

/// One rating sample — the settled rating after a completed round.
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
    /// Bulk sibling: inserts progress rows for every id not already attempted,
    /// in one fetch and one save.
    func markAttempted(_ puzzleIds: [String])
    func markFailed(_ puzzleId: String)
    func hasAttempted(_ puzzleId: String) -> Bool
    func isCompleted(_ puzzleId: String) -> Bool
    func completedCount() -> Int
    func failedCount() -> Int
    /// Favorites (only completable puzzles, enforced by the caller): stamp or
    /// clear the heart, creating the progress row if needed.
    func setFavorite(_ puzzleId: String, _ favorite: Bool)
    func isFavorite(_ puzzleId: String) -> Bool
    /// All favorited puzzle ids — drives the favorites list.
    func favoriteIDs() -> Set<String>
}

/// One row per completed round.
@MainActor
public protocol RoundHistoryRepository: AnyObject {
    func recordRound(puzzles: [Puzzle], outcomes: [PuzzleOutcome?])
    func history() -> [RoundSummary]
}

/// One rating sample per completed round.
@MainActor
public protocol RatingHistoryRepository: AnyObject {
    func recordRatingSnapshot(value: Int)
    /// All samples oldest-first, ready for a trend chart.
    func ratingHistory() -> [RatingSample]
}

/// Umbrella over the four data ports: one adapter object, one test fake.
/// `deleteAllData` is the debug "back to first launch" primitive.
@MainActor
public protocol PuzzleDataRepositories: PuzzleLibraryRepository,
    PuzzleProgressRepository, RoundHistoryRepository, RatingHistoryRepository {
    /// Deletes every row across all four stores (library, progress, history,
    /// rating snapshots).
    func deleteAllData()
}

/// Persisted round state (active round identity + start time).
@MainActor
public protocol RoundStateRepository: AnyObject {
    func startTime() -> Date?
    func activePuzzleIDs() -> [String]
    func begin(_ puzzles: [Puzzle], at start: Date)
}

/// First-launch bulk import of the bundled library.
@MainActor
public protocol LibraryImporting: AnyObject {
    /// Returns the number of chunks that failed to decode (0 = success).
    func importAllBundled(progress: @escaping @Sendable (Double) -> Void) async -> Int
}

// MARK: - Chunked delivery

/// Fetches one remote puzzle chunk. `nil` means the chunk does not exist yet
/// (HTTP 404) — the caller stops asking for higher sequences this session.
@MainActor
public protocol PuzzleChunkFetching: AnyObject {
    func fetchChunk(_ sequence: Int) async throws -> [Puzzle]?
}

/// The outcome of one provisioning check, for UI feedback.
public enum ProvisionOutcome: Sendable, Equatable {
    /// The pool already had enough unattempted puzzles; nothing was fetched.
    case skipped
    /// `count` new puzzles were imported from the next chunk.
    case added(count: Int)
    /// The remote answered 404 — the next chunk isn't published. Latched for
    /// the session.
    case notPublished
    /// The fetch failed (offline, timeout, malformed data). Selection
    /// fallbacks keep the app playable.
    case failed
}

/// Keeps the local library stocked: when fewer than `minimum` unattempted
/// puzzles remain, the next chunk is fetched and imported. Failures are
/// reported, not thrown — the existing selection fallbacks still guarantee a
/// playable round.
@MainActor
public protocol PuzzleProvisioning: AnyObject {
    func ensureRoundAvailable(minimum: Int) async -> ProvisionOutcome
}
