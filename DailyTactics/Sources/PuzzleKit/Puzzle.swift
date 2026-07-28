import Foundation

enum PuzzleTheme: String, Codable, CaseIterable, Sendable {
    case fork
    case pin
    case skewer
    case discoveredAttack
    case sacrifice
    case mate
    case defensiveMove
    case endgame
}

struct Puzzle: Identifiable, Sendable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int?
    let themes: [PuzzleTheme]

    static let sample = Puzzle(
        id: "sample-001",
        fen: "r3k2r/p1pp1p1p/b1p3p1/3nP3/1bP5/NP6/P3QPPP/R3KB1R w KQkq - 1",
        moves: ["e1d1", "d5c3", "d1c2", "c3e2"],
        rating: nil,
        themes: [.sacrifice, .mate]
    )
}

enum PuzzleSessionState: Equatable, Sendable {
    case loading
    case waitingForMove
    case opponentMoving
    case incorrectMove
    case solved
    case showingSolution
}

struct PuzzleSession: Sendable {
    enum SessionError: Error, Equatable {
        case emptyLine
        case invalidMove(String)
        case moveHasNoPiece(String)
    }

    let puzzle: Puzzle
    private(set) var board: Board
    private(set) var state: PuzzleSessionState
    private(set) var currentMoveIndex: Int
    private(set) var attempts: Int
    private(set) var lastMove: ChessMove?

    init(puzzle: Puzzle) throws {
        guard !puzzle.moves.isEmpty else { throw SessionError.emptyLine }
        for move in puzzle.moves where ChessMove(uci: move) == nil {
            throw SessionError.invalidMove(move)
        }
        self.puzzle = puzzle
        board = try Board(fen: puzzle.fen)
        state = .opponentMoving
        currentMoveIndex = 0
        attempts = 0
        lastMove = nil
    }

    var expectedMove: ChessMove? {
        guard puzzle.moves.indices.contains(currentMoveIndex) else { return nil }
        return ChessMove(uci: puzzle.moves[currentMoveIndex])
    }

    /// Lichess puzzle lines begin with the setup move made by the opponent.
    var userColor: PieceColor { board.sideToMove.opponent }

    mutating func submitUserMove(_ move: ChessMove) throws {
        guard state == .waitingForMove || state == .incorrectMove else { return }
        attempts += 1

        guard move == expectedMove else {
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

    mutating func applyOpponentMove() throws {
        guard state == .opponentMoving, let move = expectedMove else { return }
        guard board.apply(move) else { throw SessionError.moveHasNoPiece(move.uci) }
        lastMove = move
        currentMoveIndex += 1
        state = currentMoveIndex == puzzle.moves.count ? .solved : .waitingForMove
    }

    mutating func resumeAfterIncorrectMove() {
        if state == .incorrectMove {
            state = .waitingForMove
        }
    }

    mutating func restart() throws {
        self = try PuzzleSession(puzzle: puzzle)
    }
}
