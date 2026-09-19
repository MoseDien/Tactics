import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Hints and the scoring pipeline: rating changes, outcomes, history rows.
extension TacticsTrainingStore {
    var inReview: Bool { sessionState.session.state == .solved || sessionState.session.isReviewing }
    var hintEnabled: Bool {
        !inReview && (sessionState.session.state == .waitingForMove || sessionState.session.state == .incorrectMove)
    }
    var isReviewing: Bool { sessionState.session.isReviewing }
    var currentMoveNumber: Int { sessionState.session.currentMoveNumber }
    var totalUserMoves: Int { sessionState.session.totalUserMoves }

    /// First tap reveals (scored as a loss); second tap plays it for the player.
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

    /// Sets the failed outcome and rating loss once; retries can't stack.
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
        roundState.markCurrentPuzzleFinished()
    }
}
