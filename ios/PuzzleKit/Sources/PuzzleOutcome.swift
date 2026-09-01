import Foundation

/// Per-puzzle outcome for a round, used to drive the shared result row and
/// the persisted round history.
public enum PuzzleOutcome: Sendable, Hashable {
    case correct
    case wrong
}
