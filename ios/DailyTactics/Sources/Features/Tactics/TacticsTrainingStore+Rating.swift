import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Review stepping, hints, and the scoring pipeline: rating changes, round
/// outcomes, and history rows.
extension TacticsTrainingStore {
    /// `<`/`>` are review-only: available once the puzzle is solved (or while
    /// scrubbing the line afterwards). Disabled during active play.
    var inReview: Bool { sessionState.session.state == .solved || sessionState.session.isReviewing }
    var hintEnabled: Bool {
        !inReview && (sessionState.session.state == .waitingForMove || sessionState.session.state == .incorrectMove)
    }
    /// Once a puzzle has finished, the Hint control changes purpose: it opens
    /// a read-only replay of this puzzle rather than changing its outcome.
    var canReviewCurrentPuzzle: Bool { sessionState.currentPuzzleFinished }
    var isReviewing: Bool { sessionState.session.isReviewing }
    var currentMoveNumber: Int { sessionState.session.currentMoveNumber }
    var totalUserMoves: Int { sessionState.session.totalUserMoves }

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
            for: roundState.puzzles[roundState.currentIndex],
            at: roundState.currentIndex,
            ratingEnabled: canUpdateRating
        )
    }

    func markCurrentSolved() {
        sessionState.currentPuzzleFinished = true
        progressState.complete(
            puzzle: roundState.puzzles[roundState.currentIndex],
            at: roundState.currentIndex,
            round: roundState.puzzles,
            isRoundEnding: isLastPuzzle,
            ratingEnabled: canUpdateRating,
            usedHint: sessionState.hintMove != nil
        )
    }
}
