import Foundation
import SwiftData

/// Persisted completion state for a single puzzle, keyed by its Lichess id.
///
/// This is the "user has already done it" field: it is user/runtime state and is
/// kept separate from the static puzzle content (`Puzzle`), so the bundled data
/// stays read-only.
@Model
public final class PuzzleProgress {
    public var puzzleId: String
    public var isCompleted: Bool
    public var isAttempted: Bool = false
    public var hasFailed: Bool = false
    public var completedAt: Date?

    public init(puzzleId: String) {
        self.puzzleId = puzzleId
        self.isCompleted = false
        self.isAttempted = false
        self.hasFailed = false
        self.completedAt = nil
    }
}
