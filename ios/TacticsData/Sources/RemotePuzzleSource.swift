import Foundation
import PuzzleKit

/// Where remote puzzle chunks are served from. HTTPS-only; GitHub Pages sends
/// `access-control-allow-origin: *` and a plain 404 for unpublished chunks.
public enum RemotePuzzleCatalog {
    /// Base URL of the deployed puzzle repository.
    public static let baseURL = URL(string: "https://mosedien.github.io/Tactics/puzzles/")!

    /// `puzzle-NNNN.json` under the catalog's base URL.
    public static func url(forChunk sequence: Int) -> URL {
        baseURL.appendingPathComponent(String(format: "puzzle-%04d.json", sequence))
    }
}

/// Fetches one chunk over the network. `URLSession` is injected so tests
/// serve canned data without touching the network.
@MainActor
public final class RemotePuzzleFetcher: PuzzleChunkFetching {
    private let session: URLSession

    public init(session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    /// Returns the decoded chunk, or nil when the server answers 404 (the
    /// chunk has not been published yet). Any other failure throws.
    public func fetchChunk(_ sequence: Int) async throws -> [Puzzle]? {
        let (data, response) = try await session.data(from: RemotePuzzleCatalog.url(forChunk: sequence))
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return BundledPuzzleSource.decode(data)
    }
}

/// Remembers the highest chunk sequence already in the library (0 = the
/// app-bundled chunk) in UserDefaults, plus this session's "no more chunks"
/// latch so a 404 is not retried until the next launch.
@MainActor
public final class ChunkSequenceStore {
    private let key = "dailytactics.puzzleSequence"
    private let defaults: UserDefaults
    /// Session-only: set when the remote answers 404 for the next chunk.
    public private(set) var noMoreChunks = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The highest sequence present locally.
    public var current: Int {
        let stored = defaults.integer(forKey: key)
        return stored == 0 ? 0 : stored
    }

    public func advance(to sequence: Int) {
        let next = max(current, sequence)
        defaults.set(next, forKey: key)
    }

    public func markNoMoreChunks() {
        noMoreChunks = true
    }
}

/// Offline stand-in used by previews: reports "no more chunks" without any
/// network activity.
@MainActor
public final class NoopChunkFetcher: PuzzleChunkFetching {
    public init() {}
    public func fetchChunk(_ sequence: Int) async throws -> [Puzzle]? { nil }
}
