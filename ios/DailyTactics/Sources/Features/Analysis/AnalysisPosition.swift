import Foundation

extension Analysis {
    /// Immutable-by-convention board state; `squares` is indexed
    /// rank * 8 + file so legality checks copy one flat array.
    struct Position: Equatable, Sendable {
        static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

        var squares: [Piece?]
        var activeColor: Color
        var castling: CastlingRights
        var enPassantTarget: Square?
        var halfmoveClock: Int
        var fullmoveNumber: Int

        subscript(square: Square) -> Piece? {
            get { squares[square.index] }
            set { squares[square.index] = newValue }
        }

        static func start() -> Position {
            (try? Position(fen: startFEN))!
        }

        init(fen: String) throws {
            let fields = fen.split(separator: " ").map(String.init)
            guard (2...6).contains(fields.count) else { throw FENError.fieldCount(fields.count) }

            let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard ranks.count == 8 else { throw FENError.rankCount(ranks.count) }

            var parsed = [Piece?](repeating: nil, count: 64)
            for (row, rankString) in ranks.enumerated() {
                let rank = 7 - row  // FEN lists rank 8 first
                var file = 0
                var previousWasDigit = false
                for character in rankString {
                    if let span = character.wholeNumberValue {
                        guard (1...8).contains(span), !previousWasDigit else {
                            throw FENError.rankLength(rankString)
                        }
                        file += span
                        previousWasDigit = true
                        continue
                    }
                    guard let kind = PieceKind.from(fenLetter: character), file < 8 else {
                        throw file < 8 ? FENError.unknownPiece(character) : FENError.rankLength(rankString)
                    }
                    let color: Color = character.isUppercase ? .white : .black
                    parsed[rank * 8 + file] = Piece(color: color, kind: kind)
                    file += 1
                    previousWasDigit = false
                }
                guard file == 8 else { throw FENError.rankLength(rankString) }
            }
            squares = parsed

            switch fields[1] {
            case "w": activeColor = .white
            case "b": activeColor = .black
            case let other: throw FENError.badActiveColor(other)
            }

            var rights: CastlingRights = []
            let castlingField = fields.count > 2 ? fields[2] : "-"
            if castlingField != "-" {
                var seen = Set<Character>()
                for character in castlingField {
                    guard !seen.contains(character) else { throw FENError.badCastling(castlingField) }
                    switch character {
                    case "K": rights.insert(.whiteKingSide)
                    case "Q": rights.insert(.whiteQueenSide)
                    case "k": rights.insert(.blackKingSide)
                    case "q": rights.insert(.blackQueenSide)
                    default: throw FENError.badCastling(castlingField)
                    }
                    seen.insert(character)
                }
            }
            castling = rights

            let epField = fields.count > 3 ? fields[3] : "-"
            if epField == "-" {
                enPassantTarget = nil
            } else if let square = Square(notation: epField) {
                enPassantTarget = square
            } else {
                throw FENError.badEnPassant(epField)
            }

            halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
            fullmoveNumber = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
        }

        var fen: String {
            var rows: [String] = []
            for rank in stride(from: 7, through: 0, by: -1) {
                var row = ""
                var emptyRun = 0
                for file in 0..<8 {
                    if let piece = squares[rank * 8 + file] {
                        if emptyRun > 0 { row += "\(emptyRun)"; emptyRun = 0 }
                        let letter = String(piece.kind.fenLetter)
                        row += piece.color == .white ? letter.uppercased() : letter
                    } else {
                        emptyRun += 1
                    }
                }
                if emptyRun > 0 { row += "\(emptyRun)" }
                rows.append(row)
            }
            let ep = enPassantTarget?.notation ?? "-"
            return "\(rows.joined(separator: "/")) \(activeColor == .white ? "w" : "b") \(castling.fenField) \(ep) \(halfmoveClock) \(fullmoveNumber)"
        }

        func kingSquare(of color: Color) -> Square? {
            for index in 0..<64 where squares[index] == Piece(color: color, kind: .king) {
                return Square(index: index)
            }
            return nil
        }

        /// Scans outward from the target square: cheaper than visiting every
        /// enemy piece. Handles pawns, knights, kings, and sliders by ray.
        func isAttacked(_ target: Square, by color: Color) -> Bool {
            let pawnRank = color == .white ? target.rank - 1 : target.rank + 1
            for file in [target.file - 1, target.file + 1] {
                if let square = Square(file: file, rank: pawnRank),
                   self[square] == Piece(color: color, kind: .pawn) {
                    return true
                }
            }

            for (fileDelta, rankDelta) in Analysis.knightOffsets {
                if let square = Square(file: target.file + fileDelta, rank: target.rank + rankDelta),
                   self[square]?.color == color, self[square]?.kind == .knight {
                    return true
                }
            }

            for (fileDelta, rankDelta) in Analysis.kingOffsets {
                if let square = Square(file: target.file + fileDelta, rank: target.rank + rankDelta),
                   self[square] == Piece(color: color, kind: .king) {
                    return true
                }
            }

            for (fileDelta, rankDelta) in Analysis.diagonalDirections {
                var file = target.file + fileDelta
                var rank = target.rank + rankDelta
                while let square = Square(file: file, rank: rank) {
                    if let piece = self[square] {
                        if piece.color == color, piece.kind == .bishop || piece.kind == .queen {
                            return true
                        }
                        break
                    }
                    file += fileDelta
                    rank += rankDelta
                }
            }

            for (fileDelta, rankDelta) in Analysis.orthogonalDirections {
                var file = target.file + fileDelta
                var rank = target.rank + rankDelta
                while let square = Square(file: file, rank: rank) {
                    if let piece = self[square] {
                        if piece.color == color, piece.kind == .rook || piece.kind == .queen {
                            return true
                        }
                        break
                    }
                    file += fileDelta
                    rank += rankDelta
                }
            }
            return false
        }
    }
}

extension Analysis {
    static let knightOffsets: [(file: Int, rank: Int)] = [
        (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ]
    static let kingOffsets: [(file: Int, rank: Int)] = [
        (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
    ]
    static let diagonalDirections: [(file: Int, rank: Int)] = [
        (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]
    static let orthogonalDirections: [(file: Int, rank: Int)] = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
    ]
}
