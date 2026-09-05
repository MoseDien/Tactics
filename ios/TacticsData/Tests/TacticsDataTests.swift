import XCTest
import PuzzleKit
import ChessCore
import TacticsData
@testable import TacticsData

final class TacticsDataTests: XCTestCase {
    /// A promotion puzzle from the bundled chunk: the expected user move
    /// carries a promotion suffix, and a different promotion piece of the same
    /// pawn must not match the line (the regression the picker fixed).
    func testPromotionPuzzleRequiresExactPromotionPiece() throws {
        let chunk = try XCTUnwrap(BundledPuzzleSource.bundled.decodeBundledChunk())
        // fEIaZ expects d7d8q (queen promotion) as the final user move.
        let puzzle = try XCTUnwrap(chunk.first { $0.id == "fEIaZ" && $0.moves.contains("d7d8q") },
                                   "bundled chunk must contain the fEIaZ promotion puzzle")
        var session = try PuzzleSession(puzzle: puzzle)
        try session.applyOpponentMove()
        try session.submitUserMove(ChessMove(uci: "d6d7")!)
        try session.applyOpponentMove()

        let expected = try XCTUnwrap(session.expectedMove)
        XCTAssertEqual(expected.uci, "d7d8q")
        XCTAssertNotNil(expected.promotion)
        // The rook promotion of the same pawn must NOT equal the expected line.
        XCTAssertNotEqual(ChessMove(uci: "d7d8r")!, expected)
        // Submitting the exact expected promotion solves the line.
        try session.submitUserMove(expected)
        XCTAssertEqual(session.state, .solved)
    }

    func testAllBundledPuzzlesReplayThroughSession() throws {
        let chunk = try XCTUnwrap(BundledPuzzleSource.bundled.decodeBundledChunk(),
                                  "the bundled chunk must decode from the framework bundle")
        for puzzle in chunk {
            var session = try PuzzleSession(puzzle: puzzle)
            while session.canStepForward {
                try session.stepForward()
            }
            XCTAssertEqual(session.state, .solved, "puzzle \(puzzle.id) must replay to solved")
        }
        XCTAssertEqual(chunk.count, 1_000, "the bundled chunk holds 1000 puzzles")
    }

    // MARK: - SwiftDataRepositories

    @MainActor
    func testProgressStoreMarksCompletion() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())

        XCTAssertFalse(store.isCompleted("p1"))
        XCTAssertEqual(store.completedCount(), 0)

        store.markCompleted("p1")
        XCTAssertTrue(store.isCompleted("p1"))
        XCTAssertEqual(store.completedCount(), 1)

        // Idempotent: re-marking the same puzzle does not double-count.
        store.markCompleted("p1")
        XCTAssertEqual(store.completedCount(), 1)

        store.markCompleted("p2")
        XCTAssertEqual(store.completedCount(), 2)
    }

    @MainActor
    func testProgressStoreRecordsFailures() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())

        XCTAssertEqual(store.failedCount(), 0)

        store.markFailed("p1")
        XCTAssertEqual(store.failedCount(), 1)

        // Idempotent: repeated wrong moves on the same puzzle don't double-count.
        store.markFailed("p1")
        XCTAssertEqual(store.failedCount(), 1)

        // Failure and completion are independent counts.
        store.markFailed("p2")
        store.markCompleted("p2")
        XCTAssertEqual(store.failedCount(), 2)
        XCTAssertEqual(store.completedCount(), 1)
    }

    @MainActor
    func testSetFavoriteCreatesAndUpdatesRows() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        // No progress row yet: favoriting creates one.
        store.setFavorite("abc", true)
        XCTAssertTrue(store.isFavorite("abc"))
        // Toggling off clears the stamp.
        store.setFavorite("abc", false)
        XCTAssertFalse(store.isFavorite("abc"))
        // A row that already exists (e.g. from completion) is updated in place.
        store.markCompleted("xyz")
        store.setFavorite("xyz", true)
        XCTAssertTrue(store.isFavorite("xyz"))
        XCTAssertTrue(store.isCompleted("xyz"), "favorite must not disturb completion state")
    }

    @MainActor
    func testFavoriteIDsReturnsOnlyFavorited() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        store.setFavorite("one", true)
        store.setFavorite("two", false)
        store.markCompleted("three")
        XCTAssertEqual(store.favoriteIDs(), ["one"])
    }

    @MainActor
    func testDeleteAllDataClearsFavorites() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        store.setFavorite("gone", true)
        store.deleteAllData()
        XCTAssertTrue(store.favoriteIDs().isEmpty)
    }

    @MainActor
    func testAttemptedIDsDrivesSelectionExclusion() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        store.markAttempted("a")
        store.markAttempted("b")
        XCTAssertEqual(store.attemptedIDs(), ["a", "b"])
    }

    @MainActor
    func testRoundHistoryRoundTripsOutcomes() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let puzzles = Array(Puzzle.samples.prefix(2))
        store.recordRound(puzzles: puzzles, outcomes: [.correct, .wrong])
        store.recordRound(puzzles: puzzles, outcomes: [nil, .correct])

        let history = store.history()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].outcomes, [nil, .correct], "history is newest-first")
        XCTAssertEqual(history[0].puzzleIDs, puzzles.map(\.id))
    }

    @MainActor
    func testRatingHistoryOrdersOldestFirst() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        store.recordRatingSnapshot(value: 1500)
        store.recordRatingSnapshot(value: 1516)
        let series = store.ratingHistory()
        XCTAssertEqual(series.map(\.rating), [1500, 1516], "ratingHistory is oldest-first")
    }

    @MainActor
    func testImportAllBundledIsIdempotent() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let importer = PuzzleLibraryImporter(context: store.context)

        let failures = await importer.importAllBundled { _ in }
        XCTAssertEqual(failures, 0, "the bundled chunk must decode from the framework bundle")
        let firstCount = store.allPuzzles().count
        XCTAssertEqual(firstCount, 1_000)

        // Re-running must not duplicate rows (dedup by puzzleId).
        let rerunFailures = await importer.importAllBundled { _ in }
        XCTAssertEqual(rerunFailures, 0)
        XCTAssertEqual(store.allPuzzles().count, firstCount)
    }

    func testBundledChunkResourceIsPresent() {
        XCTAssertNotNil(BundledPuzzleSource.bundled.decodeBundledChunk(),
                        "puzzle-0000.json must decode from the framework bundle")
    }

    func testRemoteCatalogURLsAreWellFormed() {
        XCTAssertEqual(RemotePuzzleCatalog.url(forChunk: 0).absoluteString,
                       "https://mosedien.github.io/Tactics/puzzles/puzzle-0000.json")
        XCTAssertEqual(RemotePuzzleCatalog.url(forChunk: 12).lastPathComponent, "puzzle-0012.json")
    }

// MARK: - Chunked provisioning

/// Canned fetcher: serves programmed results per sequence without network.
@MainActor
final class FakeChunkFetcher: PuzzleChunkFetching {
    enum Result { case chunk([Puzzle]); case notFound; case failure }
    var programmed: [Int: Result] = [:]
    private(set) var requested: [Int] = []

    func fetchChunk(_ sequence: Int) async throws -> [Puzzle]? {
        requested.append(sequence)
        switch programmed[sequence] ?? .notFound {
        case .chunk(let puzzles): return puzzles
        case .notFound: return nil
        case .failure: throw URLError(.notConnectedToInternet)
        }
    }

    static func makePuzzles(_ ids: [String]) -> [Puzzle] {
        ids.map { Puzzle(id: $0, fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2", "e8e7"], rating: 1500, themes: []) }
    }
}

    @MainActor
    func makeProvisioner(attempted: [String] = []) -> (provisioner: LibraryProvisioner, store: SwiftDataRepositories, fetcher: FakeChunkFetcher, sequence: ChunkSequenceStore) {
        let defaults = UserDefaults(suiteName: "provisioner-\(UUID().uuidString)")!
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        // Seed a small library: four unattempted + the attempted ones.
        let seeded = FakeChunkFetcher.makePuzzles(["s1", "s2", "s3", "s4"] + attempted)
        for puzzle in seeded { store.context.insert(PuzzleRecord(puzzle: puzzle)) }
        try? store.context.save()
        for id in attempted { store.markAttempted(id) }
        store.invalidateLibraryCache()
        let sequence = ChunkSequenceStore(defaults: defaults)
        let fetcher = FakeChunkFetcher()
        return (LibraryProvisioner(repositories: store, sequenceStore: sequence, fetcher: fetcher), store, fetcher, sequence)
    }

    @MainActor
    func testProvisionerFetchesWhenPoolTooSmallAndInvalidatesCache() async {
        // 4 unattempted seeds < 5 → must fetch chunk 1.
        let (provisioner, store, fetcher, sequence) = makeProvisioner()
        fetcher.programmed[1] = .chunk(FakeChunkFetcher.makePuzzles((0..<5).map { "n\($0)" }))

        let outcome = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(outcome, .added(count: 5))
        XCTAssertEqual(fetcher.requested, [1])
        XCTAssertEqual(store.allPuzzles().count, 9, "cache invalidated — new rows visible")
        XCTAssertEqual(sequence.current, 1, "sequence advanced to the imported chunk")
    }

    @MainActor
    func testProvisionerSkipsWhenPoolSufficient() async {
        // 6 unattempted seeds ≥ 5 → no fetch.
        let (provisioner, store, fetcher, _) = makeProvisioner()
        for puzzle in FakeChunkFetcher.makePuzzles(["s5", "s6"]) { store.context.insert(PuzzleRecord(puzzle: puzzle)) }
        try? store.context.save()
        store.invalidateLibraryCache()

        let outcome = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertTrue(fetcher.requested.isEmpty, "no request when the pool fills a batch")
    }

    @MainActor
    func testProvisionerLatchesNoMoreChunksOn404() async {
        let (provisioner, _, fetcher, sequence) = makeProvisioner()
        // Nothing programmed → 404.
        let first = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(first, .notPublished)
        XCTAssertTrue(sequence.noMoreChunks)

        // Second call must not hit the network again this session.
        let second = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(second, .notPublished)
        XCTAssertEqual(fetcher.requested, [1], "404 latched — one request only")
    }

    @MainActor
    func testProvisionerSwallowsErrorsAndDeduplicatesIds() async {
        // Network failure → 0 inserted, no crash, sequence unchanged.
        let (provisioner, store, fetcher, sequence) = makeProvisioner()
        fetcher.programmed[1] = .failure
        var outcome = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(sequence.current, 0)

        // Chunk overlapping existing ids only inserts the new ones.
        fetcher.programmed[1] = .chunk(FakeChunkFetcher.makePuzzles(["s1", "s2", "x1", "x2", "x3"]))
        outcome = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(outcome, .added(count: 3), "duplicate ids deduped against the existing library")
        XCTAssertEqual(store.allPuzzles().count, 7)
    }

    @MainActor
    func testChunkSequenceStoreAdvancesMonotonically() {
        let defaults = UserDefaults(suiteName: "seq-\(UUID().uuidString)")!
        let store = ChunkSequenceStore(defaults: defaults)
        XCTAssertEqual(store.current, 0, "starts at the bundled chunk")
        store.advance(to: 3)
        XCTAssertEqual(store.current, 3)
        store.advance(to: 1)
        XCTAssertEqual(store.current, 3, "never regresses")
    }

    // MARK: - Full reset

    @MainActor
    func testDeleteAllDataClearsEveryTableAndCache() {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        for puzzle in FakeChunkFetcher.makePuzzles(["a", "b"]) {
            store.context.insert(PuzzleRecord(puzzle: puzzle))
        }
        store.markAttempted(["a", "b"])
        store.recordRound(puzzles: FakeChunkFetcher.makePuzzles(["a"]), outcomes: [.correct])
        store.recordRatingSnapshot(value: 1500)
        XCTAssertEqual(store.allPuzzles().count, 2)

        store.deleteAllData()

        XCTAssertTrue(store.allPuzzles().isEmpty, "cache invalidated — library empty")
        XCTAssertEqual(store.attemptedIDs(), [])
        XCTAssertTrue(store.history().isEmpty)
        XCTAssertTrue(store.ratingHistory().isEmpty)
    }

    @MainActor
    func testWipeAllRestoresEveryStoreToDefaults() {
        let defaults = UserDefaults(suiteName: "wipe-\(UUID().uuidString)")!
        defaults.set(2000, forKey: AppPreferences.userRating)
        defaults.set(Date.now, forKey: AppPreferences.batchStartTime)
        defaults.set(["x"], forKey: AppPreferences.activeBatchPuzzleIDs)
        defaults.set("hard", forKey: AppPreferences.difficultyMode)
        defaults.set(7, forKey: AppPreferences.puzzleSequence)
        defaults.set(true, forKey: AppPreferences.libraryImported)

        AppPreferences.wipeAll(defaults: defaults)

        XCTAssertEqual(UserRatingStore(defaults: defaults).rating, 1500)
        XCTAssertEqual(DifficultyModeStore(defaults: defaults).current, .medium)
        XCTAssertNil(UserDefaultsBatchStateStore(defaults: defaults).startTime())
        XCTAssertEqual(ChunkSequenceStore(defaults: defaults).current, 0)
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.libraryImported))
    }
}
