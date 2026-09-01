import Foundation
import PuzzleKit

/// Access to the 10 rating-tier JSONs bundled with this framework. Wrapping
/// `Bundle.module` behind a type keeps the app from referencing it directly
/// (the app target synthesizes its own `Bundle.module`) and lets tests point
/// at any bundle.
public struct BundledPuzzleSource: Sendable {
    public let bundle: Bundle

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// The TacticsData framework bundle containing the tier JSONs.
    public static var bundled: BundledPuzzleSource { .init(bundle: .module) }

    /// The 10 bundled rating tiers (`1000.json` … `1900.json`), each holding a
    /// 100-point band of puzzles.
    public static let tierLevels = Array(stride(from: 1000, through: 1900, by: 100))

    /// Decodes one tier, or nil when the file is missing or malformed.
    public func decodeTier(_ level: Int) -> [Puzzle]? {
        guard let url = bundle.url(forResource: "\(level)", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        struct RawPuzzle: Decodable {
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
        guard let raw = try? JSONDecoder().decode([RawPuzzle].self, from: data) else { return nil }
        return raw.map {
            Puzzle(id: $0.id, fen: $0.fen, moves: $0.moves, rating: $0.rating,
                   themes: $0.themes.compactMap(PuzzleTheme.init(rawValue:)),
                   ratingDeviation: $0.ratingDeviation, popularity: $0.popularity,
                   playCount: $0.playCount, gameUrl: $0.gameUrl, openingTags: $0.openingTags)
        }
    }
}
