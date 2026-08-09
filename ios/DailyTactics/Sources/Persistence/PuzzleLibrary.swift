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

    /// The 10 bundled rating tiers (`1000.json` … `1900.json`), each holding a
    /// 100-point band of puzzles. All of them are imported in one pass on first
    /// launch so the whole library lives in SwiftData and rounds can query it.
    static let tierLevels = Array(stride(from: 1000, through: 1900, by: 100))

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

        var puzzle: Puzzle {
            Puzzle(id: id, fen: fen, moves: moves, rating: rating,
                   themes: themes.compactMap(PuzzleTheme.init(rawValue:)),
                   ratingDeviation: ratingDeviation, popularity: popularity,
                   playCount: playCount, gameUrl: gameUrl, openingTags: openingTags)
        }
    }

    /// Bulk-import every bundled tier into SwiftData, reporting combined
    /// progress in `0...1`. Existing puzzle ids are skipped, so the call is
    /// idempotent and safe to re-run. Saves are batched every 250 inserts with
    /// a `Task.yield()` between batches to keep the loading screen responsive.
    func importAllBundled(progress: @escaping (Double) -> Void) async {
        let tiers = Self.tierLevels.compactMap { level -> [ImportPuzzle]? in
            guard let url = Bundle.main.url(forResource: "\(level)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let puzzles = try? JSONDecoder().decode([ImportPuzzle].self, from: data)
            else { return nil }
            return puzzles
        }

        let total = tiers.reduce(0) { $0 + $1.count }
        guard total > 0 else { return }

        let existingIDs = Set((try? context.fetch(FetchDescriptor<PuzzleRecord>()).map(\.puzzleId)) ?? [])
        var done = 0
        for puzzles in tiers {
            for item in puzzles {
                if !existingIDs.contains(item.id) {
                    context.insert(PuzzleRecord(puzzle: item.puzzle))
                }
                done += 1
                if done.isMultiple(of: 250) || done == total {
                    try? context.save()
                    progress(Double(done) / Double(total))
                    await Task.yield()
                }
            }
        }
    }

    /// Delete every `PuzzleRecord` and `PuzzleProgress` row. Used for a full
    /// reset; the everyday "reassess" path uses `resetProgress` instead so the
    /// imported library is not wiped.
    func reset() {
        let puzzles = (try? context.fetch(FetchDescriptor<PuzzleRecord>())) ?? []
        puzzles.forEach(context.delete)
        resetProgress()
    }

    /// Clear only the user's runtime progress (`PuzzleProgress`), leaving the
    /// imported puzzle library intact. Puzzles become unattempted again so a
    /// reassessment starts from a clean slate without re-importing 10k rows.
    func resetProgress() {
        let progress = (try? context.fetch(FetchDescriptor<PuzzleProgress>())) ?? []
        progress.forEach(context.delete)
        try? context.save()
    }
}

/// Tracks whether the bundled puzzle library has been bulk-imported into
/// SwiftData. A first-launch gate independent of the rating assessment. Views
/// observe `importedKey` via `@AppStorage` so completing the import re-renders
/// the root routing without manual state plumbing.
@MainActor
struct LibraryStateStore {
    static let importedKey = "dailytactics.libraryImported"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isImported: Bool { defaults.bool(forKey: Self.importedKey) }

    func markImported() {
        defaults.set(true, forKey: Self.importedKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.importedKey)
    }
}

