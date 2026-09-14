import PuzzleKit
import ChessCore

/// Cross-store sessionState.session coordination. The chess interaction itself is owned by
/// `TacticsSessionStore`; this adapter records its business consequences.
extension TacticsTrainingStore {
    func loadPuzzle(at index: Int) {
        do {
            let puzzle = roundState.puzzles[index]
            sessionState.reset(
                with: try PuzzleSession(puzzle: puzzle),
                favorite: roundState.repositories?.isFavorite(puzzle.id) ?? false
            )
            progressState.beginPuzzle()
            Task { await playOpponentMove() }
        } catch {
            sessionState.errorMessage = String(localized: "tactics.error_load")
        }
    }

    func attemptMove(from origin: Square, to target: Square, promotion: PieceKind? = nil) {
        handle(sessionState.submit(from: origin, to: target, promotion: promotion))
    }

    func select(_ square: Square) {
        if let event = sessionState.select(square, canInteract: canInteractWithPuzzle) {
            handle(event)
        }
    }

    func choosePromotion(_ kind: PieceKind) {
        if let event = sessionState.choosePromotion(kind) { handle(event) }
    }

    func playOpponentMove() async {
        let solved = await sessionState.applyOpponentMove(after: pacing.opponentReplyDelay)
        if solved, roundState.mode == .play { markCurrentSolved() }
    }

    func handle(_ event: TacticsSessionEvent) {
        switch event {
        case .ignored, .awaitingPromotion:
            break
        case .hintRevealed:
            settlePuzzleAsFailed()
        case let .incorrect(move, firstAttemptCorrect):
            recordFirstAttempt(correct: firstAttemptCorrect)
            settlePuzzleAsFailed()
            sessionState.demonstrateWrongMove(move, pacing: pacing)
        case let .solved(firstAttemptCorrect):
            recordFirstAttempt(correct: firstAttemptCorrect)
            markCurrentSolved()
        case let .opponentMoving(firstAttemptCorrect):
            recordFirstAttempt(correct: firstAttemptCorrect)
            Task { await playOpponentMove() }
        }
    }

    private func recordFirstAttempt(correct: Bool) {
        progressState.recordFirstAttempt(for: roundState.puzzles[roundState.currentIndex], correct: correct)
    }
}
