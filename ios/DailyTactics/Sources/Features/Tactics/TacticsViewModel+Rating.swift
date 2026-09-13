import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Review stepping, hints, and the scoring pipeline: rating changes, round
/// outcomes, and history rows.
extension TacticsTrainingStore {
    /// `<`/`>` are review-only: available once the puzzle is solved (or while
    /// scrubbing the line afterwards). Disabled during active play.
    var inReview: Bool { session.state == .solved || session.isReviewing }
    var hintEnabled: Bool {
        !inReview && (session.state == .waitingForMove || session.state == .incorrectMove)
    }
    /// Once a puzzle has finished, the Hint control changes purpose: it opens
    /// a read-only replay of this puzzle rather than changing its outcome.
    var canReviewCurrentPuzzle: Bool { currentPuzzleFinished }
    var isReviewing: Bool { session.isReviewing }
    var currentMoveNumber: Int { session.currentMoveNumber }
    var totalUserMoves: Int { session.totalUserMoves }

    /// Two-stage hint: the first tap reveals the expected move (highlighted,
    /// scored immediately as a loss); the second tap plays it for the player.
    /// The penalty already settled on the first tap, so the auto-play itself
    /// costs nothing further.
    func requestHint() {
        handleHintEvent(sessionState.requestHint())
    }

    /// Charge the rating for using a hint, once per puzzle. Idempotent so
    /// repeated taps don't stack penalties.
    private func handleHintEvent(_ event: TacticsSessionEvent) {
        if case .hintRevealed = event {
            settlePuzzleAsFailed()
        } else {
            handle(event)
        }
    }

    /// A wrong move or hint fixes the puzzle outcome as failed and applies the
    /// rating loss once. The player can still finish the line, but retries and
    /// additional hints cannot stack another penalty.
    func settlePuzzleAsFailed() {
        progressState.settleFailure(
            for: puzzles[currentIndex],
            at: currentIndex,
            ratingEnabled: canUpdateRating
        )
    }

    func markCurrentSolved() {
        currentPuzzleFinished = true
        progressState.complete(
            puzzle: puzzles[currentIndex],
            at: currentIndex,
            round: puzzles,
            isRoundEnding: isLastPuzzle,
            ratingEnabled: canUpdateRating,
            usedHint: hintMove != nil
        )
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
