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
    case advantage
    case middlegame
    case rookEndgame
    case short
}

struct Puzzle: Identifiable, Codable, Sendable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int?
    let themes: [PuzzleTheme]

    /// Lichess metadata imported for future use (statistics, filtering, links).
    /// Optional so datasets without them still decode.
    let ratingDeviation: Int?
    let popularity: Int?
    let playCount: Int?
    let gameUrl: String?
    let openingTags: [String]?

    init(
        id: String,
        fen: String,
        moves: [String],
        rating: Int?,
        themes: [PuzzleTheme],
        ratingDeviation: Int? = nil,
        popularity: Int? = nil,
        playCount: Int? = nil,
        gameUrl: String? = nil,
        openingTags: [String]? = nil
    ) {
        self.id = id
        self.fen = fen
        self.moves = moves
        self.rating = rating
        self.themes = themes
        self.ratingDeviation = ratingDeviation
        self.popularity = popularity
        self.playCount = playCount
        self.gameUrl = gameUrl
        self.openingTags = openingTags
    }

    static let samples: [Puzzle] = [
        Puzzle(
            id: "sample-001",
            fen: "r3k2r/p1pp1p1p/b1p3p1/3nP3/1bP5/NP6/P3QPPP/R3KB1R w KQkq - 1",
            moves: ["e1d1", "d5c3", "d1c2", "c3e2"],
            rating: 1017,
            themes: [.sacrifice, .mate]
        ),
        Puzzle(
            id: "sample-002",
            fen: "r2qr1k1/b1p2ppp/pp4n1/P1P1p3/4P1n1/B2P2Pb/3NBP1P/RN1QR1K1 b",
            moves: ["b6c5", "e2g4", "h3g4", "d1g4"],
            rating: 1084,
            themes: [.advantage, .middlegame, .short]
        ),
        Puzzle(
            id: "sample-003",
            fen: "8/4R3/1p2P3/p4r2/P6p/1P3Pk1/4K3/8 w - - 1 64",
            moves: ["e7f7", "f5e5", "e2f1", "e5e6"],
            rating: 1383,
            themes: [.advantage, .endgame, .rookEndgame, .short]
        )
    ]
}

enum PuzzleSessionState: Equatable, Sendable {
    case waitingForMove
    case opponentMoving
    case incorrectMove
    case solved
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
    private(set) var lastMove: ChessMove?
    /// The side the user controls, fixed for the whole line. Derived from the
    /// FEN's initial side to move — the machine opens, so the user is always
    /// the opponent of whoever moves first. Kept separate from `board.sideToMove`,
    /// which toggles as the line advances.
    let userColor: PieceColor
    /// True while the displayed position was reached by stepping rather than by
    /// the live solve flow. The view uses this to avoid the "opponent is moving"
    /// spinner during review, and the auto-reply ignores it.
    private(set) var isReviewing: Bool = false

    init(puzzle: Puzzle) throws {
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

    var expectedMove: ChessMove? {
        guard puzzle.moves.indices.contains(currentMoveIndex) else { return nil }
        return ChessMove(uci: puzzle.moves[currentMoveIndex])
    }

    /// Whether `move` is a legal chess move for the side the user controls.
    func isLegalUserMove(_ move: ChessMove) -> Bool {
        board.isLegal(move, for: userColor)
    }

    /// Whether `move` sends a pawn to its promotion rank, so the UI should
    /// ask which piece to promote to.
    func moveNeedsPromotion(_ move: ChessMove) -> Bool {
        board.isPromotion(move, for: userColor)
    }

    mutating func submitUserMove(_ move: ChessMove) throws {
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

    mutating func applyOpponentMove() throws {
        // The live solve flow keeps isReviewing false, so the auto-reply only
        // fires for the expected opponent reply — never during manual review.
        guard state == .opponentMoving, !isReviewing, let move = expectedMove else { return }
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

    // MARK: - Review stepping

    /// The 1-based number of the user move awaiting a guess, clamped to the
    /// total number of user moves in the line.
    var currentMoveNumber: Int {
        min((currentMoveIndex + 1) / 2, totalUserMoves)
    }

    /// How many moves the user must make to complete the tactical line.
    var totalUserMoves: Int { puzzle.moves.count / 2 }

    /// Whether the user may step forward to reveal the next ply.
    var canStepForward: Bool { currentMoveIndex < puzzle.moves.count }

    /// Whether the user may step back, never below the solving start position.
    var canStepBack: Bool { currentMoveIndex > 1 }

    /// Reveal the next ply of the solution — the user's move or the opponent's reply.
    mutating func stepForward() throws {
        guard currentMoveIndex < puzzle.moves.count else { return }
        try replay(to: currentMoveIndex + 1)
    }

    /// Take back one ply, never below the position where the user starts solving.
    mutating func stepBack() throws {
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

    mutating func restart() throws {
        self = try PuzzleSession(puzzle: puzzle)
    }
}
