import Foundation

enum PieceColor: String, Codable, Sendable {
    case white
    case black

    var opponent: Self { self == .white ? .black : .white }
}

enum PieceKind: String, Codable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}

struct Piece: Equatable, Sendable {
    let color: PieceColor
    let kind: PieceKind

    var assetName: String {
        switch (color, kind) {
        case (.white, .king): "wK"
        case (.white, .queen): "wQ"
        case (.white, .rook): "wR"
        case (.white, .bishop): "wB"
        case (.white, .knight): "wN"
        case (.white, .pawn): "wP"
        case (.black, .king): "bK"
        case (.black, .queen): "bQ"
        case (.black, .rook): "bR"
        case (.black, .bishop): "bB"
        case (.black, .knight): "bN"
        case (.black, .pawn): "bP"
        }
    }
}

struct Square: Hashable, Sendable {
    let file: Int
    let rank: Int

    init(file: Int, rank: Int) {
        precondition((0..<8).contains(file) && (0..<8).contains(rank))
        self.file = file
        self.rank = rank
    }

    init?(notation: String) {
        let characters = Array(notation.lowercased())
        guard characters.count == 2,
              let fileValue = characters[0].asciiValue,
              let rank = Int(String(characters[1])),
              (97...104).contains(fileValue),
              (1...8).contains(rank)
        else { return nil }
        self.init(file: Int(fileValue - 97), rank: rank - 1)
    }

    var notation: String {
        "\(Character(UnicodeScalar(UInt8(file + 97))))\(rank + 1)"
    }
}

struct ChessMove: Equatable, Sendable {
    let from: Square
    let to: Square
    let promotion: PieceKind?

    init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    init?(uci: String) {
        guard uci.count == 4 || uci.count == 5 else { return nil }
        let characters = Array(uci.lowercased())
        guard let from = Square(notation: String(characters[0...1])),
              let to = Square(notation: String(characters[2...3]))
        else { return nil }

        let promotion: PieceKind?
        if characters.count == 5 {
            switch characters[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        } else {
            promotion = nil
        }

        self.init(from: from, to: to, promotion: promotion)
    }

    var uci: String {
        let suffix: String
        switch promotion {
        case .queen: suffix = "q"
        case .rook: suffix = "r"
        case .bishop: suffix = "b"
        case .knight: suffix = "n"
        default: suffix = ""
        }
        return from.notation + to.notation + suffix
    }
}

struct Board: Equatable, Sendable {
    enum FENError: Error, Equatable {
        case missingFields
        case invalidRankCount
        case invalidRank(String)
        case invalidPiece(Character)
        case invalidSideToMove(String)
    }

    private(set) var pieces: [Square: Piece]
    let sideToMove: PieceColor

    init(fen: String) throws {
        let fields = fen.split(separator: " ")
        guard fields.count >= 2 else { throw FENError.missingFields }

        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { throw FENError.invalidRankCount }

        var parsedPieces: [Square: Piece] = [:]
        for (rankIndex, encodedRank) in ranks.enumerated() {
            var file = 0
            for character in encodedRank {
                if let emptyCount = character.wholeNumberValue {
                    guard (1...8).contains(emptyCount) else {
                        throw FENError.invalidRank(String(encodedRank))
                    }
                    file += emptyCount
                } else {
                    guard file < 8, let piece = Self.piece(for: character) else {
                        throw FENError.invalidPiece(character)
                    }
                    parsedPieces[Square(file: file, rank: 7 - rankIndex)] = piece
                    file += 1
                }
            }
            guard file == 8 else { throw FENError.invalidRank(String(encodedRank)) }
        }

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: throw FENError.invalidSideToMove(String(fields[1]))
        }
        pieces = parsedPieces
    }

    mutating func apply(_ move: ChessMove) -> Bool {
        guard let movingPiece = pieces.removeValue(forKey: move.from) else { return false }
        let targetWasEmpty = pieces[move.to] == nil
        let resultingKind = move.promotion ?? movingPiece.kind
        pieces[move.to] = Piece(color: movingPiece.color, kind: resultingKind)

        // Castling: a king advancing two files also relocates the corner rook.
        if movingPiece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6, let rook = pieces.removeValue(forKey: Square(file: 7, rank: rank)) {
                pieces[Square(file: 5, rank: rank)] = rook
            } else if move.to.file == 2, let rook = pieces.removeValue(forKey: Square(file: 0, rank: rank)) {
                pieces[Square(file: 3, rank: rank)] = rook
            }
        }

        // En passant: a pawn moving diagonally onto an empty square captures the
        // enemy pawn that just advanced beside its origin.
        if movingPiece.kind == .pawn,
           move.from.file != move.to.file,
           targetWasEmpty {
            pieces[Square(file: move.to.file, rank: move.from.rank)] = nil
        }

        return true
    }

    private static func piece(for character: Character) -> Piece? {
        let color: PieceColor = character.isUppercase ? .white : .black
        let kind: PieceKind
        switch character.lowercased() {
        case "k": kind = .king
        case "q": kind = .queen
        case "r": kind = .rook
        case "b": kind = .bishop
        case "n": kind = .knight
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(color: color, kind: kind)
    }
}

extension Board {
    /// Whether `move` is a legal move for `mover` under basic piece-movement rules.
    ///
    /// Validates movement shape, path blocking, and self-capture. It does **not**
    /// cover check/pin legality, castling, en passant, or promotion — those are
    /// deferred per the project's phased roadmap.
    func isLegal(_ move: ChessMove, for mover: PieceColor) -> Bool {
        guard let piece = pieces[move.from], piece.color == mover else { return false }
        if let occupant = pieces[move.to], occupant.color == mover { return false }
        return Self.shapeIsLegal(piece, from: move.from, to: move.to, in: pieces)
    }

    private static func shapeIsLegal(
        _ piece: Piece,
        from: Square,
        to: Square,
        in pieces: [Square: Piece]
    ) -> Bool {
        let fileDelta = to.file - from.file
        let rankDelta = to.rank - from.rank
        guard fileDelta != 0 || rankDelta != 0 else { return false }

        switch piece.kind {
        case .knight:
            return (abs(fileDelta), abs(rankDelta)) == (1, 2)
                || (abs(fileDelta), abs(rankDelta)) == (2, 1)
        case .bishop:
            return abs(fileDelta) == abs(rankDelta) && pathIsClear(from: from, to: to, in: pieces)
        case .rook:
            return (fileDelta == 0 || rankDelta == 0) && pathIsClear(from: from, to: to, in: pieces)
        case .queen:
            let straight = fileDelta == 0 || rankDelta == 0
            let diagonal = abs(fileDelta) == abs(rankDelta)
            return (straight || diagonal) && pathIsClear(from: from, to: to, in: pieces)
        case .king:
            return max(abs(fileDelta), abs(rankDelta)) == 1
        case .pawn:
            return pawnShapeIsLegal(piece, from: from, to: to, in: pieces)
        }
    }

    private static func pawnShapeIsLegal(
        _ pawn: Piece,
        from: Square,
        to: Square,
        in pieces: [Square: Piece]
    ) -> Bool {
        let fileDelta = to.file - from.file
        let rankDelta = to.rank - from.rank
        let direction = pawn.color == .white ? 1 : -1
        let startRank = pawn.color == .white ? 1 : 6

        // Forward push: one square, or two from the starting rank. Target must be empty.
        if fileDelta == 0 {
            if rankDelta == direction, pieces[to] == nil { return true }
            if from.rank == startRank, rankDelta == 2 * direction {
                let middle = Square(file: from.file, rank: from.rank + direction)
                return pieces[to] == nil && pieces[middle] == nil
            }
            return false
        }
        // Diagonal capture: one file over, one rank forward, onto an enemy piece.
        if abs(fileDelta) == 1, rankDelta == direction {
            return pieces[to]?.color == pawn.color.opponent
        }
        return false
    }

    private static func pathIsClear(from: Square, to: Square, in pieces: [Square: Piece]) -> Bool {
        let stepFile = (to.file - from.file).signum()
        let stepRank = (to.rank - from.rank).signum()
        var file = from.file + stepFile
        var rank = from.rank + stepRank
        while file != to.file || rank != to.rank {
            if pieces[Square(file: file, rank: rank)] != nil { return false }
            file += stepFile
            rank += stepRank
        }
        return true
    }
}
