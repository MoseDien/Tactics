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
        "\(Character(UnicodeScalar(file + 97)!))\(rank + 1)"
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
        let resultingKind = move.promotion ?? movingPiece.kind
        pieces[move.to] = Piece(color: movingPiece.color, kind: resultingKind)
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
