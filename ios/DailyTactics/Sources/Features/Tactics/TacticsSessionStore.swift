import ChessCore
import Observation
import PuzzleKit

enum TacticsSessionEvent {
    case ignored
    case awaitingPromotion
    case hintRevealed
    case incorrect(ChessMove, firstAttemptCorrect: Bool)
    case solved(firstAttemptCorrect: Bool)
    case opponentMoving(firstAttemptCorrect: Bool)
}

/// Mutable state for the currently displayed puzzle. It intentionally owns no
/// repository or round-selection policy: `TacticsTrainingStore` coordinates
/// those cross-feature actions and reports results to `TacticsProgressStore`.
@MainActor
@Observable
final class TacticsSessionStore {
    var session: PuzzleSession
    var selectedSquare: Square?
    var attemptedMove: ChessMove?
    var snapbackMove: ChessMove?
    var hintMove: ChessMove?
    var errorMessage: String?
    var pendingPromotion: (from: Square, to: Square)?
    var currentPuzzleFinished = false
    var isBoardFlipped = false
    var isCurrentFavorite = false
    var boardGeneration = 0
    var boardMoveRevision = 0

    init(session: PuzzleSession) {
        self.session = session
    }

    var position: [Square: Piece] { session.board.pieces }
    var lastMove: ChessMove? { session.lastMove }
    var displayedPosition: [Square: Piece] {
        guard let attempt = attemptedMove, let piece = position[attempt.from] else {
            return position
        }
        var preview = position
        preview.removeValue(forKey: attempt.from)
        preview[attempt.to] = piece
        return preview
    }
    var animatedArrival: [Square: Square] {
        if let attempt = attemptedMove { return [attempt.to: attempt.from] }
        if let snapbackMove { return [snapbackMove.from: snapbackMove.to] }
        guard let move = session.lastMove else { return [:] }
        var arrivals = [move.to: move.from]
        if let rook = session.castlingRookMove() { arrivals[rook.to] = rook.from }
        return arrivals
    }
    var isSnapbackRender: Bool { attemptedMove == nil && snapbackMove != nil }

    func reset(with session: PuzzleSession, favorite: Bool) {
        self.session = session
        boardGeneration += 1
        currentPuzzleFinished = false
        selectedSquare = nil
        hintMove = nil
        attemptedMove = nil
        snapbackMove = nil
        errorMessage = nil
        pendingPromotion = nil
        isCurrentFavorite = favorite
        isBoardFlipped = session.userColor == .black
    }

    func toggleBoardFlip() { isBoardFlipped.toggle() }

    func select(_ square: Square, canInteract: Bool) -> TacticsSessionEvent? {
        guard canInteract else { return nil }
        if attemptedMove != nil { snapbackMove = attemptedMove }
        attemptedMove = nil
        hintMove = nil
        if session.state == .incorrectMove { session.resumeAfterIncorrectMove() }
        if let selectedSquare {
            if selectedSquare == square {
                self.selectedSquare = nil
                pendingPromotion = nil
                return nil
            }
            if position[square]?.color == session.userColor {
                self.selectedSquare = square
                pendingPromotion = nil
                return nil
            }
            return submit(from: selectedSquare, to: square)
        }
        if position[square]?.color == session.userColor { selectedSquare = square }
        return nil
    }

    func choosePromotion(_ kind: PieceKind) -> TacticsSessionEvent? {
        guard let pending = pendingPromotion else { return nil }
        pendingPromotion = nil
        selectedSquare = nil
        return submit(from: pending.from, to: pending.to, promotion: kind)
    }

    func requestHint() -> TacticsSessionEvent {
        let canUseHint = !session.isReviewing
            && session.state != .solved
            && (session.state == .waitingForMove || session.state == .incorrectMove)
        guard canUseHint, let expected = session.expectedMove else { return .ignored }
        if hintMove == nil {
            hintMove = expected
            return .hintRevealed
        }
        return submit(from: expected.from, to: expected.to, promotion: expected.promotion)
    }

    func submit(from origin: Square, to target: Square, promotion: PieceKind? = nil) -> TacticsSessionEvent {
        hintMove = nil
        snapbackMove = attemptedMove ?? snapbackMove
        attemptedMove = nil
        let plain = ChessMove(from: origin, to: target)
        guard !session.moveNeedsPromotion(plain) || promotion != nil else {
            pendingPromotion = (origin, target)
            return .awaitingPromotion
        }
        let move = ChessMove(from: origin, to: target, promotion: promotion)
        let expected = move == session.expectedMove
        guard expected || session.isLegalUserMove(move) else {
            selectedSquare = nil
            return .ignored
        }
        selectedSquare = nil
        do {
            try session.submitUserMove(move)
            boardMoveRevision += 1
        } catch {
            errorMessage = String(localized: "tactics.error_apply")
            return .ignored
        }
        if session.state != .incorrectMove { snapbackMove = nil }
        switch session.state {
        case .incorrectMove: return .incorrect(move, firstAttemptCorrect: expected)
        case .solved: return .solved(firstAttemptCorrect: expected)
        case .opponentMoving: return .opponentMoving(firstAttemptCorrect: expected)
        case .waitingForMove: return .ignored
        }
    }

    func demonstrateWrongMove(_ move: ChessMove, pacing: TacticsPacing) {
        snapbackMove = nil
        attemptedMove = move
        Task { @MainActor in
            try? await Task.sleep(for: pacing.wrongMoveDisplay)
            guard !Task.isCancelled, attemptedMove == move else { return }
            snapbackMove = move
            attemptedMove = nil
            boardMoveRevision += 1
        }
    }

    func applyOpponentMove(after delay: Duration) async -> Bool {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return false }
        snapbackMove = nil
        do {
            try session.applyOpponentMove()
            boardMoveRevision += 1
            return session.state == .solved
        } catch {
            errorMessage = String(localized: "tactics.error_reply")
            return false
        }
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
