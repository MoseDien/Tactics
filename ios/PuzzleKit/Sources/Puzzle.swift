import Foundation
import ChessCore

public enum PuzzleTheme: String, Codable, CaseIterable, Sendable {
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

public struct Puzzle: Identifiable, Codable, Sendable {
    public let id: String
    public let fen: String
    public let moves: [String]
    public let rating: Int?
    public let themes: [PuzzleTheme]

    /// Lichess metadata imported for future use (statistics, filtering, links).
    /// Optional so datasets without them still decode.
    public let ratingDeviation: Int?
    public let popularity: Int?
    public let playCount: Int?
    public let gameUrl: String?
    public let openingTags: [String]?

    public init(
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

    public static let samples: [Puzzle] = [
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
