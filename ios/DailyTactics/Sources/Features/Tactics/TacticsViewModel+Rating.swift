import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Review stepping, hints, and the scoring pipeline: rating changes, round
/// outcomes, and history rows.
extension TacticsViewModel {
    /// `<`/`>` are review-only: available once the puzzle is solved (or while
    /// scrubbing the line afterwards). Disabled during active play.
    var inReview: Bool { session.state == .solved || session.isReviewing }
    var hintEnabled: Bool {
        !inReview && (session.state == .waitingForMove || session.state == .incorrectMove)
    }
    var isReviewing: Bool { session.isReviewing }
    var currentMoveNumber: Int { session.currentMoveNumber }
    var totalUserMoves: Int { session.totalUserMoves }

    /// Revealing a hint counts as giving up on this puzzle: it is scored
    /// immediately as a loss (rating decreases) and marked attempted, so a
    /// later clean solve can't recover the points.
    func requestHint() {
        guard hintEnabled, let expected = session.expectedMove else { return }
        hadMistake = true
        hintMove = expected
        applyHintPenalty()
    }

    /// Charge the rating for using a hint, once per puzzle. Idempotent so
    /// repeated taps don't stack penalties.
    func applyHintPenalty() {
        guard !ratingAppliedForPuzzle else { return }
        ratingAppliedForPuzzle = true
        recordOutcome(.wrong, for: currentIndex)
        applySolveRating(solved: false)
        progress?.markAttempted(puzzles[currentIndex].id)
    }

    func markCurrentSolved() {
        currentPuzzleFinished = true
        // Completion is recorded once regardless of the rating outcome: a hint
        // may have already adjusted the rating before the line is finished.
        progress?.markCompleted(puzzles[currentIndex].id)
        if !ratingAppliedForPuzzle {
            ratingAppliedForPuzzle = true
            recordOutcome(.correct, for: currentIndex)
        }
        // The round history is independent of the rating flow: a hint on the
        // final puzzle must not lose the whole batch's history, and re-solving
        // the batch in review must not insert it a second time.
        let isBatchEnding = isLastPuzzle && !roundRecorded
        if isBatchEnding {
            roundRecorded = true
            progress?.recordRound(puzzles: puzzles, outcomes: results)
        }
        guard canUpdateRating, firstAttemptWasCorrect else {
            // The rating was already settled (hint) or never applied; either
            // way a finishing batch still gets its snapshot.
            if isBatchEnding { progress?.recordRatingSnapshot(value: userRating) }
            return
        }
        let cleanSolve = !hadMistake && hintMove == nil
        applySolveRating(solved: cleanSolve)
        // Snapshot only after this puzzle's delta landed, so the sample is the
        // batch's final rating.
        if isBatchEnding { progress?.recordRatingSnapshot(value: userRating) }
    }

    /// Applies an Elo-style rating change for the current puzzle and persists it.
    func applySolveRating(solved: Bool) {
        guard canUpdateRating else { return }
        let puzzleRating = puzzles[currentIndex].rating ?? userRating
        let delta = ratingCalculator.change(
            userRating: userRating,
            puzzleRating: puzzleRating,
            solved: solved
        )
        userRating = ratingStore.apply(delta: delta)
        lastRatingDelta = delta
    }

    func recordFailure() {
        guard let progress else { return }
        progress.markFailed(puzzles[currentIndex].id)
    }

    /// Mark a round outcome for the puzzle at `index`. Idempotent: the first
    /// recorded result (e.g. a wrong move) wins, so a later clean solve can't
    /// overwrite an earlier mistake.
    func recordOutcome(_ outcome: PuzzleOutcome, for index: Int) {
        guard results.indices.contains(index), results[index] == nil else { return }
        results[index] = outcome
    }
}

extension PuzzleSession {
    /// Stand-in session for a puzzle that failed to build. Shows an empty
    /// board in the error state instead of crashing the app.
    static func empty() -> PuzzleSession {
        try! PuzzleSession(puzzle: Puzzle(
            id: "empty",
            fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
            moves: ["e1e2", "e8e7"],
            rating: nil,
            themes: []
        ))
    }
}
