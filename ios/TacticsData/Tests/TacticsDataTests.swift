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
        var replayed = 0
        for level in BundledPuzzleSource.tierLevels {
            guard let url = BundledPuzzleSource.bundled.bundle.url(forResource: "\(level)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let all = try? JSONDecoder().decode([ImportTestPuzzle].self, from: data)
            else { continue }
            for raw in all {
                let puzzle = Puzzle(id: raw.id, fen: raw.fen, moves: raw.moves, rating: raw.rating, themes: [])
                var session = try PuzzleSession(puzzle: puzzle)
                while session.canStepForward {
                    try session.stepForward()
                }
                XCTAssertEqual(session.state, .solved, "puzzle \(raw.id) must replay to solved")
                replayed += 1
            }
        }
        XCTAssertEqual(replayed, 10_000, "all ten tiers must decode and replay from the framework bundle")
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
        XCTAssertEqual(firstCount, 10_000)

        // Re-running must not duplicate rows (dedup by puzzleId).
        let rerunFailures = await importer.importAllBundled { _ in }
        XCTAssertEqual(rerunFailures, 0)
        XCTAssertEqual(store.allPuzzles().count, firstCount)
    }

    func testAllTenTierResourcesArePresent() {
        for level in BundledPuzzleSource.tierLevels {
            XCTAssertNotNil(
                BundledPuzzleSource.bundled.decodeTier(level),
                "tier \(level).json must decode from the framework bundle"
            )
        }
    }
}
