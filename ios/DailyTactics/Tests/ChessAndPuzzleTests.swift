import XCTest
import PuzzleKit
import ChessCore
import TacticsData
@testable import DailyTactics

final class ChessAndPuzzleTests: XCTestCase {
    @MainActor
    func testBoardAutoOrientsToPlayerColor() async throws {
        // A single-puzzle dataset makes the "which puzzle loaded" variable
        // deterministic, so the orientation invariant is actually exercised.
        let vm = TacticsViewModel(dataset: Array(Puzzle.samples.prefix(1)))
        XCTAssertEqual(vm.isBoardFlipped, vm.playerColor == .black)

        // After the machine's opening move the orientation must still hold.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 40 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.isBoardFlipped, vm.playerColor == .black)
    }
    @MainActor
    func testRatingStoreClampsToRange() {
        let defaults = UserDefaults(suiteName: "rating-clamp-\(UUID().uuidString)")!
        let store = UserRatingStore(defaults: defaults)

        store.set(rating: 2995)
        _ = store.apply(delta: 100)
        XCTAssertEqual(store.rating, 3000, "rating clamps at the ceiling")

        store.set(rating: 405)
        _ = store.apply(delta: -100)
        XCTAssertEqual(store.rating, 400, "rating clamps at the floor")

        store.reset()
        XCTAssertEqual(store.rating, 1500, "a fresh store starts at 1500")
    }
    func testDifficultyModeFilteringUsesRatingBounds() {
        let puzzles = [
            Puzzle(id: "easy", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1200, themes: []),
            Puzzle(id: "mid", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1500, themes: []),
            Puzzle(id: "hard", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1900, themes: [])
        ]
        let selector = RoundSelector()
        let easy = selector.select(library: puzzles, attempted: [], difficulty: .easy, userRating: 1500, count: 1)
        let hard = selector.select(library: puzzles, attempted: [], difficulty: .hard, userRating: 1500, count: 1)
        XCTAssertTrue(easy.allSatisfy { ($0.rating ?? 0) <= 1700 })
        XCTAssertTrue(hard.allSatisfy { ($0.rating ?? 0) >= 1300 })
    }

    @MainActor
    func testHintImmediatelyCostsRating() async throws {
        let defaults = UserDefaults(suiteName: "hint-penalty-\(UUID().uuidString)")!
        let store = UserRatingStore(defaults: defaults)
        let vm = TacticsViewModel(dataset: Array(Puzzle.samples.prefix(1)), ratingStore: store)

        // Wait for the opening machine move so a hint is enabled. Generous
        // bound keeps this stable under CI load; it waits only as long as needed.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)

        let before = vm.userRating
        vm.requestHint()

        // Using a hint is a failure: rating drops right away and the round
        // marker records it as wrong.
        XCTAssertLessThan(vm.userRating, before, "Hint should cost rating points")
        XCTAssertLessThan(vm.lastRatingDelta ?? 0, 0, "Hint should record a negative delta")

        // A second tap must not stack another penalty.
        let afterFirstHint = vm.userRating
        vm.requestHint()
        XCTAssertEqual(vm.userRating, afterFirstHint)
    }

    // MARK: - Round history records exactly once per batch

    @MainActor
    func testRoundHistoryRecordsOnceDespiteHintOnLastPuzzleAndReviewReplay() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())

        // One puzzle in the dataset so it is also the last puzzle of the batch.
        let puzzle = Puzzle.samples[0]
        let vm = TacticsViewModel(dataset: [puzzle], progress: store, dailyPuzzleCount: 1)

        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)

        // Hint on the (only, thus last) puzzle…
        vm.requestHint()

        // …then play the expected line through to solved. The old code lost
        // the round here; the new code must still record it exactly once.
        try await solveActivePuzzle(on: vm)
        XCTAssertEqual(store.history().count, 1, "hint on the last puzzle must not lose the round record")

        // Re-solving the batch in review must not insert a second row.
        vm.startNextBatch()  // inside the cooldown: stays on the same batch
        try await solveActivePuzzle(on: vm)
        XCTAssertEqual(store.history().count, 1, "review replay must not duplicate the round record")
        // Same idempotency for the rating snapshot.
        XCTAssertEqual(store.ratingHistory().count, 1, "review replay must not duplicate the rating snapshot")
    }

    @MainActor
    func testRatingSnapshotRecordedPerBatchWithFinalDelta() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let defaults = UserDefaults(suiteName: "rating-snapshot-\(UUID().uuidString)")!
        let ratingStore = UserRatingStore(defaults: defaults)

        // Single-puzzle batch solved cleanly: the snapshot must capture the
        // rating AFTER the last puzzle's delta landed, not before.
        let vm = TacticsViewModel(dataset: Array(Puzzle.samples.prefix(1)), progress: store, ratingStore: ratingStore, dailyPuzzleCount: 1)
        let ratingBefore = vm.userRating

        vm.start()
        try await waitForWaitingForMove(on: vm)
        try await solveActivePuzzle(on: vm)

        XCTAssertEqual(store.ratingHistory().count, 1, "one snapshot per completed batch")
        let snapshot = try XCTUnwrap(store.ratingHistory().first)
        XCTAssertEqual(snapshot.rating, vm.userRating,
                       "snapshot must equal the settled rating (hint-free solve moves it)")
        XCTAssertNotEqual(snapshot.rating, ratingBefore,
                          "a clean first-attempt solve must have moved the rating into the snapshot")

        // Sorting contract for the chart: oldest first.
        store.recordRatingSnapshot(value: snapshot.rating + 10)
        let series = store.ratingHistory()
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.first?.rating, snapshot.rating, "ratingHistory is oldest-first")
    }

    /// Drives the view model through the expected line of the active puzzle
    /// until solved, waiting out the opponent-reply delays.
    /// Waits (bounded) for the machine's opening move so user input is accepted.
    @MainActor
    private func waitForWaitingForMove(on vm: TacticsViewModel) async throws {
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)
    }

    @MainActor
    private func solveActivePuzzle(on vm: TacticsViewModel) async throws {
        var guardCount = 0
        while vm.state != .solved && guardCount < 150 {
            if vm.state == .waitingForMove, let expected = vm.sessionForTest().expectedMove {
                if vm.selectedSquare == nil {
                    vm.select(expected.from)
                } else {
                    // A pending promotion (not in the samples) would need a
                    // piece choice; supply the expected one.
                    if vm.pendingPromotionForTest() != nil {
                        vm.choosePromotion(expected.promotion ?? .queen)
                    } else {
                        vm.select(expected.to)
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            guardCount += 1
        }
        XCTAssertEqual(vm.state, .solved)
    }

    // MARK: - Round selection

    func testRoundSelectionExcludesAttemptedAndFallsBack() {
        let puzzles = (0..<7).map { i in
            Puzzle(id: "p\(i)", fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2"], rating: 1500, themes: [])
        }
        let selector = RoundSelector()

        // Two attempted → returns exactly 5, none attempted.
        let round = selector.select(library: puzzles, attempted: ["p0", "p1"], difficulty: .medium, userRating: 1500, count: 5)
        XCTAssertEqual(round.count, 5)
        let roundIDs = Set(round.map(\.id))
        XCTAssertFalse(roundIDs.contains("p0"))
        XCTAssertFalse(roundIDs.contains("p1"))

        // Six of seven attempted → fewer than 5 unattempted → falls back to
        // the whole library so a round is still returned.
        let attempted6 = Set((0...6).map { "p\($0)" })
        let fallback = selector.select(library: puzzles, attempted: attempted6, difficulty: .medium, userRating: 1500, count: 5)
        XCTAssertEqual(fallback.count, 5)
    }
}
