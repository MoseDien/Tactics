import Foundation
import PuzzleKit
import SwiftData

/// The imported puzzle library row.
@Model
public final class PuzzleRecord {
    @Attribute(.unique) public var puzzleId: String
    public var fen: String
    public var moves: [String]
    public var rating: Int
    public var ratingDeviation: Int?
    public var popularity: Int?
    public var playCount: Int?
    public var themes: [String]
    public var gameUrl: String?
    public var openingTags: [String]?

    public init(puzzle: Puzzle) {
        puzzleId = puzzle.id
        fen = puzzle.fen
        moves = puzzle.moves
        rating = puzzle.rating ?? 1500
        ratingDeviation = puzzle.ratingDeviation
        popularity = puzzle.popularity
        playCount = puzzle.playCount
        themes = puzzle.themes.map(\.rawValue)
        gameUrl = puzzle.gameUrl
        openingTags = puzzle.openingTags
    }

    public var puzzle: Puzzle {
        Puzzle(id: puzzleId, fen: fen, moves: moves, rating: rating, themes: themes.compactMap(PuzzleTheme.init(rawValue:)), ratingDeviation: ratingDeviation, popularity: popularity, playCount: playCount, gameUrl: gameUrl, openingTags: openingTags)
    }
}
