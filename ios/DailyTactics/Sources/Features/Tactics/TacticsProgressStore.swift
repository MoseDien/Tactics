import Foundation
import Observation
import PuzzleKit
import TacticsData

/// Owns persisted progress, round outcomes, and rating changes; the sole
/// writer of scoring and history rules.
@MainActor
@Observable
final class TacticsProgressStore {
    private let repositories: (any PuzzleDataRepositories)?
    private let ratingStore: UserRatingStore
    private let ratingCalculator = PuzzleRatingCalculator()

    private(set) var userRating: Int
    private(set) var lastRatingDelta: Int?
    private(set) var outcomes: [PuzzleOutcome?]
    private var hadMistake = false
    private var ratingAppliedForPuzzle = false
    private var firstAttemptWasCorrect = false
    private var roundRecorded = false

    init(
        repositories: (any PuzzleDataRepositories)?,
        ratingStore: UserRatingStore,
        puzzleCount: Int
    ) {
        self.repositories = repositories
        self.ratingStore = ratingStore
        userRating = ratingStore.rating
        outcomes = Array(repeating: nil, count: puzzleCount)
    }

    func beginRound(puzzleCount: Int) {
        outcomes = Array(repeating: nil, count: puzzleCount)
        roundRecorded = false
    }

    /// Rehydrate the result row when an active Round is resumed after process
    /// termination. A failure takes precedence because the original result is
    /// still wrong even if the player later finished the line.
    func restoreRoundOutcomes(for puzzles: [Puzzle]) {
        outcomes = puzzles.map { puzzle in
            guard let repositories else { return nil }
            if repositories.hasFailed(puzzle.id) { return .wrong }
            return repositories.isCompleted(puzzle.id) ? .correct : nil
        }
    }

    /// A cursor past the last puzzle means the closing chain — which is what
    /// advances the cursor — already ran before the kill, so its side effects
    /// are recorded and review replays must not repeat them.
    func restoreRoundRecorded(cursor: Int, puzzleCount: Int) {
        roundRecorded = cursor >= puzzleCount
    }

    func beginPuzzle() {
        hadMistake = false
        firstAttemptWasCorrect = false
        ratingAppliedForPuzzle = false
        lastRatingDelta = nil
    }

    func recordFirstAttempt(for puzzle: Puzzle, correct: Bool) {
        guard !(repositories?.hasAttempted(puzzle.id) ?? false) else { return }
        firstAttemptWasCorrect = correct
        repositories?.markAttempted(puzzle.id)
    }

    func settleFailure(for puzzle: Puzzle, at index: Int, ratingEnabled: Bool) {
        hadMistake = true
        recordOutcome(.wrong, at: index)
        repositories?.markFailed(puzzle.id)
        repositories?.markAttempted(puzzle.id)
        guard !ratingAppliedForPuzzle else { return }
        ratingAppliedForPuzzle = true
        applyRating(for: puzzle, solved: false, enabled: ratingEnabled)
    }

    func complete(
        puzzle: Puzzle,
        at index: Int,
        round: [Puzzle],
        isRoundEnding: Bool,
        ratingEnabled: Bool,
        usedHint: Bool
    ) {
        repositories?.markCompleted(puzzle.id)
        if !ratingAppliedForPuzzle {
            ratingAppliedForPuzzle = true
            recordOutcome(.correct, at: index)
        }
        // The history row and the snapshot are round-closing side effects:
        // they fire once per round, never again on review replays.
        let closesRound = isRoundEnding && !roundRecorded
        if closesRound {
            roundRecorded = true
            repositories?.recordRound(puzzles: round, outcomes: outcomes)
        }
        guard ratingEnabled, firstAttemptWasCorrect else {
            if closesRound { repositories?.recordRatingSnapshot(value: userRating) }
            return
        }
        applyRating(for: puzzle, solved: !hadMistake && !usedHint, enabled: true)
        if closesRound { repositories?.recordRatingSnapshot(value: userRating) }
    }

    private func applyRating(for puzzle: Puzzle, solved: Bool, enabled: Bool) {
        guard enabled else { return }
        let puzzleRating = puzzle.rating ?? userRating
        let delta = ratingCalculator.change(
            userRating: userRating,
            puzzleRating: puzzleRating,
            solved: solved
        )
        userRating = ratingStore.apply(delta: delta)
        lastRatingDelta = delta
    }

    private func recordOutcome(_ outcome: PuzzleOutcome, at index: Int) {
        guard outcomes.indices.contains(index), outcomes[index] == nil else { return }
        outcomes[index] = outcome
    }
}
