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
        var move = ChessMove(from: origin, to: target)
        if session.moveNeedsPromotion(move) {
            guard let promotion else {
                // The player must choose the promotion piece; the choice UI
                // is up while the move itself waits.
                pendingPromotion = (origin, target)
                return
            }
            move = ChessMove(from: origin, to: target, promotion: promotion)
        }
        // The expected move is trusted-legal (from the puzzle line), so accept
        // it even for moves the legality check would reject on partial data.
        // Any other move must be fully legal.
        let isExpected = move == session.expectedMove
        guard isExpected || session.isLegalUserMove(move) else {
            selectedSquare = nil
            return
        }

        let puzzleID = puzzles[currentIndex].id
        let isFirstAttempt = !(progress?.hasAttempted(puzzleID) ?? false)
        if isFirstAttempt {
            firstAttemptWasCorrect = isExpected
            progress?.markAttempted(puzzleID)
        }

        selectedSquare = nil
        do {
            try session.submitUserMove(move)
        } catch {
            errorMessage = String(localized: "tactics.error_apply")
            return
        }

        switch state {
        case .incorrectMove:
            // Wrong move: record it as a failure, then let the user retry.
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
        case .solved:
            markCurrentSolved()
        case .opponentMoving:
            Task { await playOpponentMove() }
        default:
            break
        }
    }

    func playOpponentMove() async {
        try? await Task.sleep(for: pacing.opponentReplyDelay)
        guard !Task.isCancelled else { return }
        snapbackMove = nil
        do {
            try session.applyOpponentMove()
        } catch {
            errorMessage = String(localized: "tactics.error_reply")
            return
        }
        if session.state == .solved && mode == .play {
            markCurrentSolved()
        }
    }
}
