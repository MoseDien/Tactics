import Foundation

/// Namespace for the free analysis board's clean-room types. Nesting keeps
/// these names from shadowing the ChessCore types used unqualified elsewhere
/// in the app target.
enum Analysis {}

extension Analysis {
    struct Square: Hashable, Sendable {
        let file: Int  // 0 = a … 7 = h
        let rank: Int  // 0 = rank 1 … 7 = rank 8

        init?(file: Int, rank: Int) {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
            self.file = file
            self.rank = rank
        }

        init?(index: Int) {
            guard (0..<64).contains(index) else { return nil }
            self.init(file: index % 8, rank: index / 8)
        }

        init?(notation: String) {
            let characters = Array(notation.lowercased())
            guard characters.count == 2,
                  let fileValue = characters.first?.asciiValue,
                  let rank = characters.last.flatMap({ Int(String($0)) }),
                  (97...104).contains(fileValue),
                  (1...8).contains(rank)
            else { return nil }
            self.init(file: Int(fileValue - 97), rank: rank - 1)
        }

        var index: Int { rank * 8 + file }
        var notation: String { "\(Character(UnicodeScalar(UInt8(file + 97))))\(rank + 1)" }
    }

    enum Color: String, Sendable {
        case white, black

        var opposite: Self { self == .white ? .black : .white }
    }

    enum PieceKind: String, Sendable {
        case king, queen, rook, bishop, knight, pawn

        /// FEN letter, lowercase (callers uppercase for white).
        var fenLetter: Character {
            switch self {
            case .king: "k"
            case .queen: "q"
            case .rook: "r"
            case .bishop: "b"
            case .knight: "n"
            case .pawn: "p"
            }
        }

        static func from(fenLetter: Character) -> PieceKind? {
            switch fenLetter.lowercased() {
            case "k": .king
            case "q": .queen
            case "r": .rook
            case "b": .bishop
            case "n": .knight
            case "p": .pawn
            default: nil
            }
        }
    }

    struct Piece: Hashable, Sendable {
        let color: Color
        let kind: PieceKind

        /// Matches the chessnut imageset names in the app asset catalog.
        var assetName: String {
            let side = color == .white ? "w" : "b"
            switch kind {
            case .king: return side + "K"
            case .queen: return side + "Q"
            case .rook: return side + "R"
            case .bishop: return side + "B"
            case .knight: return side + "N"
            case .pawn: return side + "P"
            }
        }
    }

    struct Move: Hashable, Sendable {
        let from: Square
        let to: Square
        let promotion: PieceKind?

        init(from: Square, to: Square, promotion: PieceKind? = nil) {
            self.from = from
            self.to = to
            self.promotion = promotion
        }
    }

    struct CastlingRights: OptionSet, Sendable {
        let rawValue: UInt8

        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let whiteKingSide = CastlingRights(rawValue: 1 << 0)
        static let whiteQueenSide = CastlingRights(rawValue: 1 << 1)
        static let blackKingSide = CastlingRights(rawValue: 1 << 2)
        static let blackQueenSide = CastlingRights(rawValue: 1 << 3)

        var fenField: String {
            var field = ""
            if contains(.whiteKingSide) { field += "K" }
            if contains(.whiteQueenSide) { field += "Q" }
            if contains(.blackKingSide) { field += "k" }
            if contains(.blackQueenSide) { field += "q" }
            return field.isEmpty ? "-" : field
        }
    }

    enum FENError: Error, Equatable {
        case fieldCount(Int)
        case rankCount(Int)
        case rankLength(String)
        case unknownPiece(Character)
        case badActiveColor(String)
        case badCastling(String)
        case badEnPassant(String)
    }
}
