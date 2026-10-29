import XCTest
import PuzzleKit
import ChessCore
import TacticsData
@testable import DailyTactics

/// The Home card's derived state: round status, progress, the new-round
/// window, and the start-next-round path shared with the board.
@MainActor
final class HomeViewModelTests: XCTestCase {

    /// Fresh install: the store's convenience init auto-begins round one, so
    /// the card shows an in-progress round at puzzle 1 with the window locked.
    func testFreshInstallShowsInProgressRoundAtPuzzleOne() async throws {
        let dependencies = makeDependencies()
        let failures = await dependencies.importer.importAllBundled { _ in }
        XCTAssertEqual(failures, 0)

        let home = HomeViewModel(
            training: TacticsTrainingStore(dependencies: dependencies, dailyPuzzleCount: RoundPolicy.puzzleCount)
        )

        XCTAssertFalse(home.isReviewingRound)
        XCTAssertEqual(home.puzzleNumber, 1)
        XCTAssertEqual(home.puzzleCount, RoundPolicy.puzzleCount)
        XCTAssertEqual(home.solvedCount, 0)
        XCTAssertEqual(home.outcomes.count, RoundPolicy.puzzleCount)
        XCTAssertTrue(home.outcomes.allSatisfy { $0 == nil })
        XCTAssertFalse(home.isNewRoundAvailable)
        XCTAssertNotNil(home.nextRoundUnlockDescription)
    }

    /// A resumed round continues at its persisted cursor, still in play.
    func testResumedRoundReflectsPersistedCursor() async throws {
        let dependencies = makeDependencies()
        let failures = await dependencies.importer.importAllBundled { _ in }
        XCTAssertEqual(failures, 0)

        let round = Array(dependencies.data.allPuzzles().prefix(3))
        dependencies.round.begin(round)
        dependencies.round.setNextPuzzleIndex(1)

        let home = HomeViewModel(
            training: TacticsTrainingStore(
                dependencies: dependencies,
                dailyPuzzleCount: 3,
                mode: .play,
                resumesActiveRound: true
            )
        )

        XCTAssertEqual(home.puzzleNumber, 2)
        XCTAssertEqual(home.puzzleCount, 3)
        XCTAssertFalse(home.isReviewingRound)
    }

    /// Inside the window the new-round action is locked and the unlock time
    /// is shown; the foreground refresh at expiry flips both.
    func testWindowLockThenExpiryRefreshTogglesNewRoundAvailability() {
        let clock = MutableClock()
        let tracker = RoundTracker(state: InMemoryRoundState(), now: { clock.now })
        let puzzles = Array(Puzzle.samples.prefix(2))
        tracker.begin(puzzles)

        let training = TacticsTrainingStore(dataset: puzzles, dailyPuzzleCount: 2, mode: .reviewRound)
        training.roundState.tracker = tracker
        let home = HomeViewModel(training: training)

        XCTAssertFalse(home.isNewRoundAvailable)
        XCTAssertNotNil(home.nextRoundUnlockDescription)

        // This mirrors the refresh performed when the app becomes active.
        clock.advance(RoundPolicy.roundDuration)
        tracker.refresh()

        XCTAssertTrue(home.isNewRoundAvailable)
        XCTAssertNil(home.nextRoundUnlockDescription)
    }

    /// The completed-round card shows review status, and the Home-triggered
    /// start of the next round follows the board's guarded path: play mode,
    /// a fresh batch excluding the previous one, progress reset.
    func testCompletedRoundShowsReviewAndStartsANewRound() async throws {
        let dependencies = makeDependencies()
        let failures = await dependencies.importer.importAllBundled { _ in }
        XCTAssertEqual(failures, 0)

        let previous = Array(dependencies.data.allPuzzles().prefix(3))
        let clock = MutableClock()
        let tracker = RoundTracker(state: InMemoryRoundState(), now: { clock.now })
        tracker.begin(previous)
        tracker.setRoundMode(TacticsMode.reviewRound.persistedLabel)

        let training = TacticsTrainingStore(
            dataset: previous,
            progress: dependencies.data,
            dailyPuzzleCount: 3,
            mode: .reviewRound
        )
        training.roundState.tracker = tracker
        training.roundState.difficultyStore = dependencies.difficulty
        training.roundState.provisioner = dependencies.provisioner
        let home = HomeViewModel(training: training)
        XCTAssertTrue(home.isReviewingRound)

        clock.advance(RoundPolicy.roundDuration)
        tracker.refresh()
        XCTAssertTrue(home.isNewRoundAvailable)

        training.startNextRound()
        XCTAssertEqual(training.roundState.mode, .play, "mode flips synchronously under the window guard")

        var waited = 0
        while training.roundState.puzzles.map(\.id) == previous.map(\.id) && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertNotEqual(training.roundState.puzzles.map(\.id), previous.map(\.id), "the new batch excludes the previous round")
        XCTAssertEqual(home.puzzleNumber, 1)
        XCTAssertTrue(home.outcomes.allSatisfy { $0 == nil }, "progress resets for the new round")
    }

    /// Solving the round's only puzzle flips the card to review with the
    /// solved tally.
    func testSolvedRoundShowsReviewStatusAndSolvedCount() async throws {
        let store = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let puzzle = Puzzle.samples[0]
        let tracker = RoundTracker(state: InMemoryRoundState())
        tracker.begin([puzzle])

        let training = TacticsTrainingStore(dataset: [puzzle], progress: store, dailyPuzzleCount: 1)
        training.roundState.tracker = tracker

        training.start()
        try await waitForWaitingForMove(on: training)
        try await solveActivePuzzle(on: training)

        let home = HomeViewModel(training: training)
        XCTAssertTrue(home.isReviewingRound)
        XCTAssertEqual(home.solvedCount, 1)
        XCTAssertEqual(home.outcomes, [.correct])
    }

    // MARK: - Helpers

    private func makeDependencies() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "home-vm-\(UUID().uuidString)")!
        let repositories = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        let sequenceStore = ChunkSequenceStore(defaults: defaults)
        return AppDependencies(
            data: repositories,
            importer: PuzzleLibraryImporter(context: repositories.context),
            round: RoundTracker(state: UserDefaultsRoundStateStore(defaults: defaults)),
            difficulty: DifficultyModeStore(defaults: defaults),
            userRating: UserRatingStore(defaults: defaults),
            provisioner: LibraryProvisioner(
                repositories: repositories,
                sequenceStore: sequenceStore,
                fetcher: NoopChunkFetcher()
            ),
            sequenceStore: sequenceStore,
            pacing: TacticsPacing()
        )
    }

    /// Waits (bounded) for the machine's opening move so user input is accepted.
    private func waitForWaitingForMove(on vm: TacticsTrainingStore) async throws {
        var waited = 0
        while vm.state != .waitingForMove && waited < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)
    }

    /// Drives the view model through the expected line of the active puzzle
    /// until solved, waiting out the opponent-reply delays.
    private func solveActivePuzzle(on vm: TacticsTrainingStore) async throws {
        var guardCount = 0
        while vm.state != .solved && guardCount < 150 {
            if vm.state == .waitingForMove, let expected = vm.sessionForTest().expectedMove {
                if vm.sessionState.selectedSquare == nil {
                    vm.select(expected.from)
                } else if vm.pendingPromotionForTest() != nil {
                    vm.choosePromotion(expected.promotion ?? .queen)
                } else {
                    vm.select(expected.to)
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            guardCount += 1
        }
        XCTAssertEqual(vm.state, .solved)
    }
}
