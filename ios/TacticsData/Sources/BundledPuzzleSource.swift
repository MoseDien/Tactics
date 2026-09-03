import Foundation
import PuzzleKit

/// Access to the app-bundled puzzle chunk. Wrapping `Bundle.module` behind a
/// type keeps the app from referencing it directly (the app target synthesizes
/// its own `Bundle.module`) and lets tests point at any bundle.
public struct BundledPuzzleSource: Sendable {
    let bundle: Bundle

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// The TacticsData framework bundle containing the bundled chunk.
    public static var bundled: BundledPuzzleSource { .init(bundle: .module) }

    /// The chunk shipped inside the app (`puzzle-0000.json`); further chunks
    /// arrive over the network.
    static let bundledChunkName = "puzzle-0000"

    /// Decodes the bundled chunk, or nil when the file is missing or malformed.
    public func decodeBundledChunk() -> [Puzzle]? {
        guard let url = bundle.url(forResource: BundledPuzzleSource.bundledChunkName, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return Self.decode(data)
    }

    /// Shared decoder used by the bundled source and the remote fetcher so
    /// both produce identical `Puzzle` values.
    public static func decode(_ data: Data) -> [Puzzle]? {
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
