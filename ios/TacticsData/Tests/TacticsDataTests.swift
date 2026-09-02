import XCTest
import PuzzleKit
import ChessCore
import TacticsData
@testable import TacticsData

final class TacticsDataTests: XCTestCase {
    func testUnderpromotionPuzzlesSolveWithChosenPromotionPiece() throws {
        // Bundled puzzles that expect an under-promotion (o8GIU: rook,
        // LnGZ6: knight). They were unsolvable when the UI forced queen.
        let expectations: [(file: String, id: String)] = [("1000", "o8GIU"), ("1100", "LnGZ6")]
        for spec in expectations {
            guard let url = Bundle.main.url(forResource: spec.file, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let all = try? JSONDecoder().decode([ImportTestPuzzle].self, from: data),
                  let raw = all.first(where: { $0.id == spec.id })
            else { continue } // resource absent in some test hosts

            let puzzle = Puzzle(id: raw.id, fen: raw.fen, moves: raw.moves, rating: raw.rating, themes: [])
            var session = try PuzzleSession(puzzle: puzzle)
            try session.applyOpponentMove()

            // The expected move carries the under-promotion suffix; submitting
            // the exact move must be accepted (not .incorrectMove).
            let expected = try XCTUnwrap(session.expectedMove)
            XCTAssertNotNil(expected.promotion, "expected move \(expected.uci) must carry a promotion suffix")
            try session.submitUserMove(expected)
            XCTAssertNotEqual(session.state, .incorrectMove, "under-promotion \(expected.uci) must be accepted")

            // A queen promotion of the same pawn must NOT match the expected
            // line — this is the exact regression the picker fixes.
            if let queenMove = ChessMove(uci: expected.uci.dropLast().appending("q").description) {
                XCTAssertNotEqual(queenMove, expected, "queen variant must differ from an under-promotion line")
            }
        }
    }

    private struct ImportTestPuzzle: Decodable {
        let id: String
        let fen: String
        let moves: [String]
        let rating: Int?
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
        XCTAssertEqual(failures, 0, "every bundled tier must decode from the framework bundle")
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

        let inserted = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(inserted, 5)
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

        let inserted = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(inserted, 0)
        XCTAssertTrue(fetcher.requested.isEmpty, "no request when the pool fills a batch")
    }

    @MainActor
    func testProvisionerLatchesNoMoreChunksOn404() async {
        let (provisioner, _, fetcher, sequence) = makeProvisioner()
        // Nothing programmed → 404.
        let first = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(first, 0)
        XCTAssertTrue(sequence.noMoreChunks)

        // Second call must not hit the network again this session.
        _ = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(fetcher.requested, [1], "404 latched — one request only")
    }

    @MainActor
    func testProvisionerSwallowsErrorsAndDeduplicatesIds() async {
        // Network failure → 0 inserted, no crash, sequence unchanged.
        let (provisioner, store, fetcher, sequence) = makeProvisioner()
        fetcher.programmed[1] = .failure
        var inserted = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(inserted, 0)
        XCTAssertEqual(sequence.current, 0)

        // Chunk overlapping existing ids only inserts the new ones.
        fetcher.programmed[1] = .chunk(FakeChunkFetcher.makePuzzles(["s1", "s2", "x1", "x2", "x3"]))
        inserted = await provisioner.ensureBatchAvailable(minimum: 5)
        XCTAssertEqual(inserted, 3, "duplicate ids deduped against the existing library")
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
}
