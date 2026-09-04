import Foundation

public struct Square: Hashable, Sendable {
    public let file: Int
    public let rank: Int

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    public init?(notation: String) {
        let characters = Array(notation.lowercased())
        guard characters.count == 2,
              let fileValue = characters[0].asciiValue,
              let rank = Int(String(characters[1])),
              (97...104).contains(fileValue),
              (1...8).contains(rank)
        else { return nil }
        // The guard bounds both values to the board, so this cannot be nil.
        self.init(file: Int(fileValue - 97), rank: rank - 1)!
    }

    public var notation: String {
        "\(Character(UnicodeScalar(UInt8(file + 97))))\(rank + 1)"
    }
}

public struct ChessMove: Equatable, Sendable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public init?(uci: String) {
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

    public var uci: String {
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
