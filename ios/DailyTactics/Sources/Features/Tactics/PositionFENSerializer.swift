import ChessCore
import PuzzleKit

/// Serializes the training board into the FEN the analysis feature consumes.
/// Lives at the feature boundary: the analysis engine itself stays free of
/// ChessCore types.
enum PositionFENSerializer {
    /// The analysis board seeds from the puzzle's raw FEN and receives the
    /// machine's setup move separately — the analysis engine plays it as
    /// history frame one, so the board can rewind through it. The live
    /// training session is deliberately ignored, which may be midway through
    /// a line or in review.
    static func analysisSeed(for puzzle: Puzzle) -> (fen: String, openingMove: Analysis.Move?) {
        guard var session = try? PuzzleSession(puzzle: puzzle) else {
            return (puzzle.fen, nil)
        }
        try? session.applyOpponentMove()
        return (puzzle.fen, openingMove(from: session.lastMove))
    }

    /// ChessCore move → analysis move at the feature boundary; nil when the
    /// move or either square falls outside the analysis board.
    private static func openingMove(from move: ChessMove?) -> Analysis.Move? {
        guard let move,
              let from = Analysis.Square(file: move.from.file, rank: move.from.rank),
              let to = Analysis.Square(file: move.to.file, rank: move.to.rank)
        else { return nil }
        let promotion = move.promotion.flatMap { Analysis.PieceKind(rawValue: $0.rawValue) }
        return Analysis.Move(from: from, to: to, promotion: promotion)
    }

    static func fen(from board: Board) -> String {
        var grid = [ChessCore.Piece?](repeating: nil, count: 64)
        for (square, piece) in board.pieces {
            grid[square.rank * 8 + square.file] = piece
        }

        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var emptyRun = 0
            for file in 0..<8 {
                if let piece = grid[rank * 8 + file] {
                    if emptyRun > 0 { row += "\(emptyRun)"; emptyRun = 0 }
                    let letter = String(fenLetter(for: piece.kind))
                    row += piece.color == .white ? letter.uppercased() : letter
                } else {
                    emptyRun += 1
                }
            }
            if emptyRun > 0 { row += "\(emptyRun)" }
            rows.append(row)
        }

        var rights = ""
        if board.castlingRights.contains(.whiteKingSide) { rights += "K" }
        if board.castlingRights.contains(.whiteQueenSide) { rights += "Q" }
        if board.castlingRights.contains(.blackKingSide) { rights += "k" }
        if board.castlingRights.contains(.blackQueenSide) { rights += "q" }
        if rights.isEmpty { rights = "-" }

        let active = board.sideToMove == .white ? "w" : "b"
        let enPassant = board.enPassantTarget?.notation ?? "-"
        return "\(rows.joined(separator: "/")) \(active) \(rights) \(enPassant) 0 1"
    }

    private static func fenLetter(for kind: PieceKind) -> Character {
        switch kind {
        case .king: "k"
        case .queen: "q"
        case .rook: "r"
        case .bishop: "b"
        case .knight: "n"
        case .pawn: "p"
        }
    }
}
