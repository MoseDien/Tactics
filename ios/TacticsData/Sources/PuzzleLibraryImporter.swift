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

    /// Bulk-import every bundled tier into SwiftData, reporting combined
    /// progress in `0...1`. Existing puzzle ids are skipped, so the call is
    /// idempotent and safe to re-run.
    ///
    /// JSON reading and decoding run off the main actor; only the SwiftData
    /// inserts (which must stay on the context's actor) remain on it. Returns
    /// the number of tiers that failed to decode — the caller must not flip
    /// the first-launch gate when it is non-zero, or the app would silently
    /// degrade to the bundled samples forever.
    @discardableResult
    public func importAllBundled(progress: @escaping @Sendable (Double) -> Void) async -> Int {
        let source = self.source
        let tiers: [[Puzzle]] = await Task.detached(priority: .userInitiated) {
            BundledPuzzleSource.tierLevels.compactMap { source.decodeTier($0) }
        }.value

        let failedTiers = BundledPuzzleSource.tierLevels.count - tiers.count
        let total = tiers.reduce(0) { $0 + $1.count }
        guard total > 0 else { return max(failedTiers, 1) }

        let existingIDs = Set((try? context.fetch(FetchDescriptor<PuzzleRecord>()).map(\.puzzleId)) ?? [])
        var done = 0
        for puzzles in tiers {
            for puzzle in puzzles {
                if Task.isCancelled { return failedTiers }
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
        }
        return failedTiers
    }
}

/// Tracks whether the bundled puzzle library has been bulk-imported into
/// SwiftData. A first-launch gate independent of puzzle play. Views observe
/// `importedKey` via `@AppStorage` so completing the import re-renders the
/// root routing without manual state plumbing.
@MainActor
public struct LibraryStateStore {
    public static let importedKey = "dailytactics.libraryImported"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isImported: Bool { defaults.bool(forKey: Self.importedKey) }

    public func markImported() {
        defaults.set(true, forKey: Self.importedKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.importedKey)
    }
}
