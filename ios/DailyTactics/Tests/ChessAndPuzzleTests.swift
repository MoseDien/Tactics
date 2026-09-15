import XCTest
import PuzzleKit
import ChessCore
import TacticsData
@testable import DailyTactics

final class ChessAndPuzzleTests: XCTestCase {
    func testLaunchResumesAPersistedRoundInReviewMode() {
        // Inside its window or expired alike — starting a fresh round is a
        // user action, never automatic on launch.
        for inWindow in [true, false] {
            let configuration = TacticsLaunchConfiguration.resolve(
                activePuzzleIDs: ["puzzle-1", "puzzle-2"],
                isWithinWindow: inWindow
            )
            XCTAssertTrue(configuration.resumesActiveRound)
            XCTAssertEqual(configuration.mode, .reviewRound)
        }
    }

    func testLaunchCreatesAPlayRoundOnlyWithNothingPersisted() {
        XCTAssertEqual(
            TacticsLaunchConfiguration.resolve(activePuzzleIDs: [], isWithinWindow: true),
            TacticsLaunchConfiguration(mode: .play, resumesActiveRound: false)
        )
    }

    @MainActor
    func testResumedRoundStartsAtItsPersistedCursor() {
        let round = TacticsRoundStore(
            puzzles: Array(Puzzle.samples.prefix(3)),
            repositories: nil,
            dailyPuzzleCount: 3,
            mode: .play
        )
        let state = InMemoryRoundState()
        let tracker = RoundTracker(state: state)
        tracker.begin(round.puzzles)
        tracker.setNextPuzzleIndex(1)
        round.tracker = tracker

        XCTAssertEqual(
            round.restorePersistedCursor(),
            1
        )
        XCTAssertEqual(round.currentIndex, 1)
    }

    @MainActor
    func testResumedRoundRestoresCompletedAndFailedOutcomeMarkers() {
        let repositories = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let puzzles = Array(Puzzle.samples.prefix(3))
        repositories.markCompleted(puzzles[0].id)
        repositories.markFailed(puzzles[1].id)

        let progress = TacticsProgressStore(
            repositories: repositories,
            ratingStore: UserRatingStore(defaults: UserDefaults(suiteName: "restored-outcomes-\(UUID().uuidString)")!),
            puzzleCount: puzzles.count
        )
        progress.restoreRoundOutcomes(for: puzzles)

        XCTAssertEqual(progress.outcomes[0], .correct)
        XCTAssertEqual(progress.outcomes[1], .wrong)
        XCTAssertNil(progress.outcomes[2])
    }

    @MainActor
    func testBoardAutoOrientsToPlayerColor() async throws {
        // A single-puzzle dataset makes the "which puzzle loaded" variable
        // deterministic, so the orientation invariant is actually exercised.
        let vm = TacticsTrainingStore(dataset: Array(Puzzle.samples.prefix(1)))
        XCTAssertEqual(vm.sessionState.isBoardFlipped, vm.playerColor == .black)

        // After the machine's opening move the orientation must still hold.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 40 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.sessionState.isBoardFlipped, vm.playerColor == .black)
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
        XCTAssertEqual(store.rating, 1000, "a fresh store starts at 1000")
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
        let progress = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let vm = TacticsTrainingStore(dataset: Array(Puzzle.samples.prefix(1)), progress: progress, ratingStore: store)

        // Wait for the opening machine move so a hint is enabled. Generous
        // bound keeps this stable under CI load; it waits only as long as needed.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)

        let before = vm.progressState.userRating
        vm.requestHint()

        // Using a hint is a failure: rating drops right away and the round
        // marker records it as wrong.
        XCTAssertLessThan(vm.progressState.userRating, before, "Hint should cost rating points")
        XCTAssertLessThan(vm.progressState.lastRatingDelta ?? 0, 0, "Hint should record a negative delta")
        XCTAssertEqual(progress.failedCount(), 1, "Hint should persist the puzzle as failed")

        // A second tap must not stack another penalty.
        let afterFirstHint = vm.progressState.userRating
        vm.requestHint()
        XCTAssertEqual(vm.progressState.userRating, afterFirstHint)
        XCTAssertEqual(progress.failedCount(), 1)
    }

    @MainActor
    func testWrongMoveImmediatelyCostsRatingAndRemainsFailedAfterSolve() async throws {
        let puzzle = Puzzle(
            id: "wrong-move-rating",
            fen: "4k3/8/8/8/8/8/4K3/8 b - - 0 1",
            moves: ["e8e7", "e2e3"],
            rating: 1500,
            themes: []
        )
        let defaults = UserDefaults(suiteName: "wrong-move-penalty-\(UUID().uuidString)")!
        let ratingStore = UserRatingStore(defaults: defaults)
        let progress = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let vm = TacticsTrainingStore(dataset: [puzzle], progress: progress, ratingStore: ratingStore, dailyPuzzleCount: 1)

        vm.start()
        try await waitForWaitingForMove(on: vm)
        let ratingBefore = vm.progressState.userRating

        vm.attemptMove(from: Square(notation: "e2")!, to: Square(notation: "d2")!)

        XCTAssertEqual(vm.state, .incorrectMove)
        XCTAssertEqual(vm.progressState.outcomes, [.wrong])
        XCTAssertEqual(progress.failedCount(), 1)
        XCTAssertLessThan(vm.progressState.userRating, ratingBefore, "A wrong move should cost rating points")
        XCTAssertLessThan(vm.progressState.lastRatingDelta ?? 0, 0, "The deducted score should be available to display")

        let ratingAfterFailure = vm.progressState.userRating
        vm.attemptMove(from: Square(notation: "e2")!, to: Square(notation: "e3")!)

        XCTAssertEqual(vm.state, .solved)
        XCTAssertTrue(vm.sessionState.currentPuzzleFinished)
        XCTAssertTrue(vm.canReviewCurrentPuzzle,
                      "a completed puzzle should make the Hint control open its single-puzzle review")
        XCTAssertEqual(vm.progressState.userRating, ratingAfterFailure, "Finishing after a mistake must not apply rating twice")
        XCTAssertLessThan(vm.progressState.lastRatingDelta ?? 0, 0)
    }

    @MainActor
    func testWrongMoveSnapbackAdvancesBoardAnimationRevision() async throws {
        let puzzle = Puzzle(
            id: "wrong-move-snapback",
            fen: "4k3/8/8/8/8/8/4K3/8 b - - 0 1",
            moves: ["e8e7", "e2e3"],
            rating: 1500,
            themes: []
        )
        let vm = TacticsTrainingStore(dataset: [puzzle], dailyPuzzleCount: 1)
        vm.pacing = TacticsPacing(
            nextPuzzleDelay: .milliseconds(1),
            wrongMoveDisplay: .milliseconds(20),
            opponentReplyDelay: .milliseconds(1)
        )

        vm.start()
        try await waitForWaitingForMove(on: vm)

        let origin = try XCTUnwrap(Square(notation: "e2"))
        let target = try XCTUnwrap(Square(notation: "d2"))
        let revisionBeforeAttempt = vm.boardMoveRevision

        vm.attemptMove(from: origin, to: target)

        XCTAssertEqual(vm.sessionState.attemptedMove, ChessMove(from: origin, to: target))
        XCTAssertEqual(vm.animatedArrival, [target: origin])
        XCTAssertEqual(vm.boardMoveRevision, revisionBeforeAttempt + 1,
                       "the wrong-move preview starts its own animation transaction")

        var waited = 0
        while vm.sessionState.attemptedMove != nil && waited < 100 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }

        XCTAssertNil(vm.sessionState.attemptedMove)
        XCTAssertEqual(vm.sessionState.snapbackMove, ChessMove(from: origin, to: target))
        XCTAssertEqual(vm.animatedArrival, [origin: target])
        XCTAssertEqual(vm.boardMoveRevision, revisionBeforeAttempt + 2,
                       "snap-back must change the observed value so SwiftUI animates the return")
    }

    // MARK: - Round history records exactly once per round

    @MainActor
    func testRoundHistoryRecordsOnceDespiteHintOnLastPuzzleAndReviewReplay() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())

        // One puzzle in the dataset so it is also the last puzzle of the round.
        let puzzle = Puzzle.samples[0]
        let vm = TacticsTrainingStore(dataset: [puzzle], progress: store, dailyPuzzleCount: 1)

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

        // Re-solving the round in review must not insert a second row.
        vm.startNextRound()  // inside the cooldown: stays on the same round
        try await solveActivePuzzle(on: vm)
        XCTAssertEqual(store.history().count, 1, "review replay must not duplicate the round record")
        // Same idempotency for the rating snapshot.
        XCTAssertEqual(store.ratingHistory().count, 1, "review replay must not duplicate the rating snapshot")
    }

    @MainActor
    func testStartNextRoundStaysInCurrentRoundDuringCooldown() {
        let clock = MutableClock()
        let state = InMemoryRoundState()
        let tracker = RoundTracker(state: state, now: { clock.now })
        let puzzles = Array(Puzzle.samples.prefix(2))
        tracker.begin(puzzles)

        let vm = TacticsTrainingStore(dataset: puzzles, dailyPuzzleCount: 2, mode: .reviewRound)
        vm.roundState.tracker = tracker
        vm.startNextRound()

        XCTAssertEqual(vm.roundState.mode, .reviewRound)
        XCTAssertEqual(vm.roundState.puzzles.map(\.id), puzzles.map(\.id))
        XCTAssertEqual(state.activePuzzleIDs(), puzzles.map(\.id))
    }

    @MainActor
    func testNewRoundActionAppearsAfterTrackerRefreshAtExpiry() {
        let clock = MutableClock()
        let tracker = RoundTracker(state: InMemoryRoundState(), now: { clock.now })
        let puzzles = Array(Puzzle.samples.prefix(2))
        tracker.begin(puzzles)

        let vm = TacticsTrainingStore(dataset: puzzles, dailyPuzzleCount: 2, mode: .reviewRound)
        vm.roundState.tracker = tracker
        XCTAssertFalse(vm.isNewRoundAvailable)
        XCTAssertFalse(vm.shouldShowNewRoundAction)

        // This mirrors the refresh performed when the app becomes active.
        clock.advance(RoundPolicy.roundDuration)
        tracker.refresh()

        XCTAssertTrue(vm.isNewRoundAvailable)
        XCTAssertTrue(vm.shouldShowNewRoundAction)
    }

    @MainActor
    func testFavoritePersistsAfterSolvingAndIgnoredBeforeCompletion() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let puzzle = Puzzle.samples[0]
        let vm = TacticsTrainingStore(dataset: [puzzle], progress: store, dailyPuzzleCount: 1)

        // Before the puzzle is finished the heart is unavailable.
        vm.toggleFavorite()
        XCTAssertFalse(vm.sessionState.isCurrentFavorite)
        XCTAssertTrue(store.favoriteIDs().isEmpty, "favoriting must be a no-op before the puzzle is finished")

        // Solve, then favorite: persists through the repository.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        try await solveActivePuzzle(on: vm)
        XCTAssertTrue(vm.sessionState.currentPuzzleFinished)

        vm.toggleFavorite()
        XCTAssertTrue(vm.sessionState.isCurrentFavorite)
        XCTAssertEqual(store.favoriteIDs(), [puzzle.id])

        // Toggling again removes it.
        vm.toggleFavorite()
        XCTAssertFalse(vm.sessionState.isCurrentFavorite)
        XCTAssertTrue(store.favoriteIDs().isEmpty)
    }

    @MainActor
    func testRatingSnapshotRecordedPerRoundWithFinalDelta() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let defaults = UserDefaults(suiteName: "rating-snapshot-\(UUID().uuidString)")!
        let ratingStore = UserRatingStore(defaults: defaults)

        // Single-puzzle round solved cleanly: the snapshot must capture the
        // rating AFTER the last puzzle's delta landed, not before.
        let vm = TacticsTrainingStore(dataset: Array(Puzzle.samples.prefix(1)), progress: store, ratingStore: ratingStore, dailyPuzzleCount: 1)
        let ratingBefore = vm.progressState.userRating

        vm.start()
        try await waitForWaitingForMove(on: vm)
        try await solveActivePuzzle(on: vm)

        XCTAssertEqual(store.ratingHistory().count, 1, "one snapshot per completed round")
        let snapshot = try XCTUnwrap(store.ratingHistory().first)
        XCTAssertEqual(snapshot.rating, vm.progressState.userRating,
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
    private func waitForWaitingForMove(on vm: TacticsTrainingStore) async throws {
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)
    }

    @MainActor
    private func solveActivePuzzle(on vm: TacticsTrainingStore) async throws {
        var guardCount = 0
        while vm.state != .solved && guardCount < 150 {
            if vm.state == .waitingForMove, let expected = vm.sessionForTest().expectedMove {
                if vm.sessionState.selectedSquare == nil {
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
