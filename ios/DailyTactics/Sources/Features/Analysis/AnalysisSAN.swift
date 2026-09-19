import Foundation

/// Score-keeping helpers for the analysis UI: SAN rendering of the played
/// line, the moving piece for each move's icon, and the material balance.
extension Analysis {
    /// One entry of the board's move strip: the move in SAN plus the piece
    /// that made it (the promoted kind for promotions) and the fullmove
    /// number the move belongs to.
    struct MoveDisplay: Equatable, Sendable {
        let san: String
        let piece: Piece
        let number: Int
    }

    enum SAN {
        /// Standard algebraic notation for `move` played from `position`,
        /// with disambiguation and check/mate suffixes.
        static func san(for move: Move, in position: Position) -> String {
            guard let mover = position[move.from] else { return move.from.notation + move.to.notation }
            let isCapture = position[move.to] != nil
                || (mover.kind == .pawn && move.to == position.enPassantTarget)

            let text: String
            if mover.kind == .king, abs(move.to.file - move.from.file) == 2 {
                text = move.to.file == 6 ? "O-O" : "O-O-O"
            } else if mover.kind == .pawn {
                let capture = isCapture ? "\(move.from.notation.prefix(1))x" : ""
                let promotion = move.promotion.map { "=\(kindLetter($0))" } ?? ""
                text = capture + move.to.notation + promotion
            } else {
                let capture = isCapture ? "x" : ""
                text = kindLetter(mover.kind)
                    + disambiguation(for: move, in: position)
                    + capture
                    + move.to.notation
            }

            switch Status.of(position.applying(move)) {
            case .checkmate: return text + "#"
            case .check: return text + "+"
            default: return text
            }
        }

        /// File, then rank, then full square — the SAN disambiguation ladder,
        /// over same-kind pieces with a legal route to the same target.
        private static func disambiguation(for move: Move, in position: Position) -> String {
            guard let mover = position[move.from] else { return "" }
            let rivals = position.squares.indices.compactMap { index -> Square? in
                guard position.squares[index] == mover,
                      let square = Square(index: index),
                      square != move.from
                else { return nil }
                return square
            }
            let ambiguous = rivals.filter { rival in
                position.legalMoves(from: rival).contains { $0.to == move.to }
            }
            guard !ambiguous.isEmpty else { return "" }
            if !ambiguous.contains(where: { $0.file == move.from.file }) {
                return String(move.from.notation.prefix(1))
            }
            if !ambiguous.contains(where: { $0.rank == move.from.rank }) {
                return String(move.from.notation.dropFirst())
            }
            return move.from.notation
        }

        private static func kindLetter(_ kind: PieceKind) -> String {
            kind == .pawn ? "" : String(kind.fenLetter).uppercased()
        }
    }
}

extension Analysis.Game {
    /// The played line rendered for the move strip, frame by frame; the
    /// machine's opening move is entry one.
    var moveList: [Analysis.MoveDisplay] {
        moves.indices.compactMap { index in
            let move = moves[index]
            let before = positions[index]
            guard let mover = before[move.from] else { return nil }
            let piece = move.promotion.map { Analysis.Piece(color: mover.color, kind: $0) } ?? mover
            return Analysis.MoveDisplay(
                san: Analysis.SAN.san(for: move, in: before),
                piece: piece,
                number: before.fullmoveNumber
            )
        }
    }
}

extension Analysis.Position {
    /// Positive means White leads. Pawn 1, knight/bishop 3, rook 5, queen 9.
    var materialBalance: Int {
        squares.compactMap { $0 }.reduce(0) { sum, piece in
            sum + (piece.color == .white ? Self.pieceValue(piece.kind) : -Self.pieceValue(piece.kind))
        }
    }

    private static func pieceValue(_ kind: Analysis.PieceKind) -> Int {
        switch kind {
        case .queen: 9
        case .rook: 5
        case .bishop, .knight: 3
        case .pawn: 1
        case .king: 0
        }
    }
}
