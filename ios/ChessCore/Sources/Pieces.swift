import Foundation

public enum PieceColor: String, Codable, Sendable {
    case white
    case black

    public var opponent: Self { self == .white ? .black : .white }
}

public enum PieceKind: String, Codable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}

public struct Piece: Equatable, Sendable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    public var assetName: String {
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
