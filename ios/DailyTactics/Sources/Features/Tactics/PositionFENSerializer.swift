import ChessCore

/// Serializes the training board into the FEN the analysis feature consumes.
/// Lives at the feature boundary: the analysis engine itself stays free of
/// ChessCore types.
enum PositionFENSerializer {
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
