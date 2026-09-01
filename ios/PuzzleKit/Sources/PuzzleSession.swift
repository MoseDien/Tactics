import Foundation
import ChessCore

public enum PuzzleSessionState: Equatable, Sendable {
    case waitingForMove
    case opponentMoving
    case incorrectMove
    case solved
}

public struct PuzzleSession: Sendable {
    public enum SessionError: Error, Equatable {
        case emptyLine
        case invalidMove(String)
        case moveHasNoPiece(String)
    }

    public let puzzle: Puzzle
    public private(set) var board: Board
    public private(set) var state: PuzzleSessionState
    public private(set) var currentMoveIndex: Int
    public private(set) var lastMove: ChessMove?
    /// The side the user controls, fixed for the whole line. Derived from the
    /// FEN's initial side to move — the machine opens, so the user is always
    /// the opponent of whoever moves first. Kept separate from `board.sideToMove`,
    /// which toggles as the line advances.
    public let userColor: PieceColor
    /// True while the displayed position was reached by stepping rather than by
    /// the live solve flow. The view uses this to avoid the "opponent is moving"
    /// spinner during review, and the auto-reply ignores it.
    public private(set) var isReviewing: Bool = false

    public init(puzzle: Puzzle) throws {
        guard !puzzle.moves.isEmpty else { throw SessionError.emptyLine }
        for move in puzzle.moves where ChessMove(uci: move) == nil {
            throw SessionError.invalidMove(move)
        }
        self.puzzle = puzzle
        board = try Board(fen: puzzle.fen)
        // Lichess puzzle lines begin with the setup move made by the machine,
        // so the user controls the opponent of the side to move in the FEN.
        userColor = board.sideToMove.opponent
        state = .opponentMoving
        currentMoveIndex = 0
        lastMove = nil
    }

    public var expectedMove: ChessMove? {
        guard puzzle.moves.indices.contains(currentMoveIndex) else { return nil }
        return ChessMove(uci: puzzle.moves[currentMoveIndex])
    }

    /// Whether `move` is a legal chess move for the side the user controls.
    public func isLegalUserMove(_ move: ChessMove) -> Bool {
        board.isLegal(move, for: userColor)
    }

    /// Whether `move` sends a pawn to its promotion rank, so the UI should
    /// ask which piece to promote to.
    public func moveNeedsPromotion(_ move: ChessMove) -> Bool {
        board.isPromotion(move, for: userColor)
    }

    public mutating func submitUserMove(_ move: ChessMove) throws {
        guard state == .waitingForMove || state == .incorrectMove else { return }
        isReviewing = false

        guard move == expectedMove else {
            // Wrong move: the view layer records it as a failure, but the user
            // may keep trying (retry in place).
            state = .incorrectMove
            return
        }

        guard board.apply(move) else { throw SessionError.moveHasNoPiece(move.uci) }
        lastMove = move
        currentMoveIndex += 1

        if currentMoveIndex == puzzle.moves.count {
            state = .solved
        } else {
            state = .opponentMoving
        }
    }

    public mutating func applyOpponentMove() throws {
        // The live solve flow keeps isReviewing false, so the auto-reply only
        // fires for the expected opponent reply — never during manual review.
        guard state == .opponentMoving, !isReviewing, let move = expectedMove else { return }
        guard board.apply(move) else { throw SessionError.moveHasNoPiece(move.uci) }
        lastMove = move
        currentMoveIndex += 1
        state = currentMoveIndex == puzzle.moves.count ? .solved : .waitingForMove
    }

    public mutating func resumeAfterIncorrectMove() {
        if state == .incorrectMove {
            state = .waitingForMove
        }
    }

    // MARK: - Review stepping

    /// The 1-based number of the user move awaiting a guess, clamped to the
    /// total number of user moves in the line.
    public var currentMoveNumber: Int {
        min((currentMoveIndex + 1) / 2, totalUserMoves)
    }

    /// How many moves the user must make to complete the tactical line.
    public var totalUserMoves: Int { puzzle.moves.count / 2 }

    /// Whether the user may step forward to reveal the next ply.
    public var canStepForward: Bool { currentMoveIndex < puzzle.moves.count }

    /// Whether the user may step back, never below the solving start position.
    public var canStepBack: Bool { currentMoveIndex > 1 }

    /// Reveal the next ply of the solution — the user's move or the opponent's reply.
    public mutating func stepForward() throws {
        guard currentMoveIndex < puzzle.moves.count else { return }
        try replay(to: currentMoveIndex + 1)
    }

    /// Take back one ply, never below the position where the user starts solving.
    public mutating func stepBack() throws {
        guard currentMoveIndex > 1 else { return }
        try replay(to: currentMoveIndex - 1)
    }

    /// Recompute the board, last move and state by replaying the first `target`
    /// moves of the line from the initial FEN. Powers the manual stepping controls.
    private mutating func replay(to target: Int) throws {
        let clamped = max(1, min(puzzle.moves.count, target))
        var rebuilt = try Board(fen: puzzle.fen)
        for uci in puzzle.moves.prefix(clamped) {
            guard let move = ChessMove(uci: uci) else {
                throw SessionError.invalidMove(uci)
            }
            guard rebuilt.apply(move) else {
                throw SessionError.moveHasNoPiece(uci)
            }
        }
        board = rebuilt
        currentMoveIndex = clamped
        lastMove = ChessMove(uci: puzzle.moves[clamped - 1])
        isReviewing = true
        if clamped == puzzle.moves.count {
            state = .solved
        } else {
            state = clamped.isMultiple(of: 2) ? .opponentMoving : .waitingForMove
        }
    }

    public mutating func restart() throws {
        self = try PuzzleSession(puzzle: puzzle)
    }
}
