import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Move submission: validating the player's move, demonstrating wrong moves,
/// playing the machine's replies, and loading puzzles into the session.
extension TacticsViewModel {
    func loadPuzzle(at index: Int) {
        do {
            session = try PuzzleSession(puzzle: puzzles[index])
            boardGenerationValue += 1
            currentPuzzleFinished = false
            selectedSquare = nil
            hintMove = nil
            attemptedMove = nil
            snapbackMove = nil
            errorMessage = nil
            batchCooldownMessage = nil
            pendingPromotion = nil
            hadMistake = false
            firstAttemptWasCorrect = false
            ratingAppliedForPuzzle = false
            lastRatingDelta = nil
            orientBoardToPlayer()
            Task { await playOpponentMove() }
        } catch {
            errorMessage = String(localized: "tactics.error_load")
        }
    }

    func attemptMove(from origin: Square, to target: Square, promotion: PieceKind? = nil) {
        hintMove = nil
        // A revert only animates the render it happens in; anything else that
        // changes the board below retires the snapback first.
        snapbackMove = nil

        guard let move = promotionResolvedMove(from: origin, to: target, promotion: promotion) else {
            // The player must choose the promotion piece; the choice UI is
            // up while the move itself waits.
            pendingPromotion = (origin, target)
            return
        }

        // The expected move is trusted-legal (from the puzzle line), so accept
        // it even for moves the legality check would reject on partial data.
        // Any other move must be fully legal.
        let isExpected = move == session.expectedMove
        guard isExpected || session.isLegalUserMove(move) else {
            selectedSquare = nil
            return
        }

        recordFirstAttempt(correct: isExpected)
        selectedSquare = nil
        do {
            try session.submitUserMove(move)
            boardMoveRevisionValue += 1
        } catch {
            errorMessage = String(localized: "tactics.error_apply")
            return
        }

        switch state {
        case .incorrectMove:
            demonstrateWrongMove(move)
        case .solved:
            markCurrentSolved()
        case .opponentMoving:
            Task { await playOpponentMove() }
        default:
            break
        }
    }

    /// The move to submit, or nil when a pawn reached the last rank and the
    /// promotion piece still has to be picked.
    private func promotionResolvedMove(from origin: Square, to target: Square, promotion: PieceKind?) -> ChessMove? {
        let plain = ChessMove(from: origin, to: target)
        guard session.moveNeedsPromotion(plain) else { return plain }
        guard let promotion else { return nil }
        return ChessMove(from: origin, to: target, promotion: promotion)
    }

    /// The first attempt on a puzzle fixes its rating outcome and marks it
    /// attempted, so retries can't game the score.
    private func recordFirstAttempt(correct: Bool) {
        let puzzleID = puzzles[currentIndex].id
        guard !(progress?.hasAttempted(puzzleID) ?? false) else { return }
        firstAttemptWasCorrect = correct
        progress?.markAttempted(puzzleID)
    }

    /// A wrong move is recorded as a failure, demonstrated on the board, and
    /// reverted after a beat so the player can retry.
    private func demonstrateWrongMove(_ move: ChessMove) {
        recordOutcome(.wrong, for: currentIndex)
        recordFailure()
        hadMistake = true
        snapbackMove = nil
        attemptedMove = move
        let attempted = move
        Task {
            try? await Task.sleep(for: pacing.wrongMoveDisplay)
            guard !Task.isCancelled, attemptedMove == attempted else { return }
            // Same render as the preview clears: the piece slides back.
            snapbackMove = attempted
            attemptedMove = nil
        }
    }

    func playOpponentMove() async {
        try? await Task.sleep(for: pacing.opponentReplyDelay)
        guard !Task.isCancelled else { return }
        snapbackMove = nil
        do {
            try session.applyOpponentMove()
            boardMoveRevisionValue += 1
        } catch {
            errorMessage = String(localized: "tactics.error_reply")
            return
        }
        if session.state == .solved && mode == .play {
            markCurrentSolved()
        }
    }
}
