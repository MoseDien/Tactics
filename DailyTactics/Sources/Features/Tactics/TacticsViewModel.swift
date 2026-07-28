import Foundation
import Observation

@MainActor
@Observable
final class TacticsViewModel {
    private(set) var session: PuzzleSession
    private(set) var selectedSquare: Square?
    private(set) var errorMessage: String?

    init(puzzle: Puzzle = .sample) {
        do {
            session = try PuzzleSession(puzzle: puzzle)
        } catch {
            preconditionFailure("Invalid bundled puzzle: \(error)")
        }
    }

    var position: [Square: Piece] { session.board.pieces }
    var state: PuzzleSessionState { session.state }
    var puzzle: Puzzle { session.puzzle }
    var playerColor: PieceColor { session.userColor }

    func start() {
        guard state == .opponentMoving, session.currentMoveIndex == 0 else { return }
        Task { await playOpponentMove() }
    }

    func select(_ square: Square) {
        guard state == .waitingForMove || state == .incorrectMove else { return }

        if state == .incorrectMove {
            session.resumeAfterIncorrectMove()
        }

        if let selectedSquare {
            if selectedSquare == square {
                self.selectedSquare = nil
            } else if position[square]?.color == session.userColor {
                self.selectedSquare = square
            } else {
                submit(ChessMove(from: selectedSquare, to: square))
            }
        } else if position[square]?.color == session.userColor {
            selectedSquare = square
        }
    }

    func restart() {
        do {
            try session.restart()
            selectedSquare = nil
            errorMessage = nil
            Task { await playOpponentMove() }
        } catch {
            errorMessage = "The puzzle could not be restarted."
        }
    }

    private func submit(_ move: ChessMove) {
        selectedSquare = nil
        do {
            try session.submitUserMove(move)
            if state == .opponentMoving {
                Task { await playOpponentMove() }
            }
        } catch {
            errorMessage = "The move could not be applied."
        }
    }

    private func playOpponentMove() async {
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do {
            try session.applyOpponentMove()
        } catch {
            errorMessage = "The reply could not be applied."
        }
    }
}
