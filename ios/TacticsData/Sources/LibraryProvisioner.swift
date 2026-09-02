import Foundation
import PuzzleKit
import SwiftData

/// Keeps the local library stocked: when the unattempted pool drops below the
/// batch size, fetches the next remote chunk and inserts it. All failures are
/// swallowed — selection's existing fallbacks keep the app playable offline.
@MainActor
public final class LibraryProvisioner: PuzzleProvisioning {
    private let repositories: SwiftDataRepositories
    private let sequenceStore: ChunkSequenceStore
    private let fetcher: any PuzzleChunkFetching

    public init(
        repositories: SwiftDataRepositories,
        sequenceStore: ChunkSequenceStore,
        fetcher: any PuzzleChunkFetching
    ) {
        self.repositories = repositories
        self.sequenceStore = sequenceStore
        self.fetcher = fetcher
    }

    public func ensureBatchAvailable(minimum: Int) async -> Int {
        let library = repositories.allPuzzles()
        let attempted = repositories.attemptedIDs()
        let unattempted = library.count - attempted.count
        if unattempted >= minimum { return 0 }

        if sequenceStore.noMoreChunks { return 0 }

        let next = sequenceStore.current + 1
        let chunk: [Puzzle]
        do {
            guard let fetched = try await fetcher.fetchChunk(next) else {
                // Not published yet; don't ask again this session.
                sequenceStore.markNoMoreChunks()
                return 0
            }
            chunk = fetched
        } catch {
            // Offline / timeout / malformed: selection falls back as before.
            return 0
        }

        let existingIDs = Set(library.map(\.id))
        var inserted = 0
        for puzzle in chunk where !existingIDs.contains(puzzle.id) {
            repositories.context.insert(PuzzleRecord(puzzle: puzzle))
            inserted += 1
        }
        try? repositories.context.save()
        sequenceStore.advance(to: next)
        repositories.invalidateLibraryCache()
        return inserted
    }
}
