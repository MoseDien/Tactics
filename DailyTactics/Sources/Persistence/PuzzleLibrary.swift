import Foundation
import SwiftData

@Model
final class PuzzleRecord {
    @Attribute(.unique) var puzzleId: String
    var fen: String
    var moves: [String]
    var rating: Int
    var ratingDeviation: Int?
    var popularity: Int?
    var playCount: Int?
    var themes: [String]
    var gameUrl: String?
    var openingTags: [String]?

    init(puzzle: Puzzle) {
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

    var puzzle: Puzzle {
        Puzzle(id: puzzleId, fen: fen, moves: moves, rating: rating, themes: themes.compactMap(PuzzleTheme.init(rawValue:)), ratingDeviation: ratingDeviation, popularity: popularity, playCount: playCount, gameUrl: gameUrl, openingTags: openingTags)
    }
}

@MainActor
struct PuzzleLibraryImporter {
    let context: ModelContext

    private struct ImportPuzzle: Decodable {
        let id: String
        let fen: String
        let moves: [String]
        let rating: Int
        let ratingDeviation: Int?
        let popularity: Int?
        let playCount: Int?
        let themes: [String]
        let gameUrl: String?
        let openingTags: [String]?
    }

    func importBundled(for rating: Int, progress: @escaping (Double) -> Void) async {
        let level = RatingLevel(rating: rating).rawValue
        guard let url = Bundle.main.url(forResource: level, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([ImportPuzzle].self, from: data)
        else { return }

        let puzzles = imported.map {
            Puzzle(id: $0.id, fen: $0.fen, moves: $0.moves, rating: $0.rating,
                   themes: $0.themes.compactMap(PuzzleTheme.init(rawValue:)),
                   ratingDeviation: $0.ratingDeviation, popularity: $0.popularity,
                   playCount: $0.playCount, gameUrl: $0.gameUrl, openingTags: $0.openingTags)
        }

        let existingIDs = Set((try? context.fetch(FetchDescriptor<PuzzleRecord>()).map(\.puzzleId)) ?? [])

        for (index, puzzle) in puzzles.enumerated() {
            if !existingIDs.contains(puzzle.id) {
                context.insert(PuzzleRecord(puzzle: puzzle))
            }
            if (index + 1).isMultiple(of: 250) || index == puzzles.count - 1 {
                try? context.save()
                progress(Double(index + 1) / Double(puzzles.count))
                await Task.yield()
            }
        }
    }

    func reset() {
        let puzzles = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        puzzles.forEach(context.delete)
        let progress = (try? context.fetch(FetchDescriptor<PuzzleProgress>())) ?? []
        progress.forEach(context.delete)
        try? context.save()
    }
}
