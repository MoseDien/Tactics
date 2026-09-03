import Foundation
import PuzzleKit
import SwiftData

/// First-launch bulk import of the bundled library into SwiftData.
@MainActor
public final class PuzzleLibraryImporter: LibraryImporting {
    let context: ModelContext
    let source: BundledPuzzleSource

    public init(context: ModelContext, source: BundledPuzzleSource = .bundled) {
        self.context = context
        self.source = source
    }

    /// Bulk-import the bundled chunk into SwiftData, reporting progress in
    /// `0...1`. Existing puzzle ids are skipped, so the call is idempotent and
    /// safe to re-run.
    ///
    /// JSON reading and decoding run off the main actor; only the SwiftData
    /// inserts (which must stay on the context's actor) remain on it. Returns
    /// 1 when the chunk failed to decode — the caller must not flip the
    /// first-launch gate then, or the app would silently degrade to the
    /// bundled samples forever.
    @discardableResult
    public func importAllBundled(progress: @escaping @Sendable (Double) -> Void) async -> Int {
        let source = self.source
        let decoded = await Task.detached(priority: .userInitiated) {
            source.decodeBundledChunk()
        }.value
        guard let puzzles = decoded, !puzzles.isEmpty else { return 1 }

        let total = puzzles.count
        let existingIDs = Set((try? context.fetch(FetchDescriptor<PuzzleRecord>()).map(\.puzzleId)) ?? [])
        var done = 0
        for puzzle in puzzles {
            if Task.isCancelled { return 0 }
            if !existingIDs.contains(puzzle.id) {
                context.insert(PuzzleRecord(puzzle: puzzle))
            }
            done += 1
            if done.isMultiple(of: 250) || done == total {
                try? context.save()
                progress(Double(done) / Double(total))
                await Task.yield()
            }
        }
        return 0
    }
}

/// The first-launch import gate's UserDefaults key. Observed via
/// `@AppStorage` so completing the import re-routes the root view.
public enum LibraryStateStore {
    public static let importedKey = "dailytactics.libraryImported"
}
