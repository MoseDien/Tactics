import XCTest
import PuzzleKit
@testable import DailyTactics

final class BatchTrackerTests: XCTestCase {
    @MainActor
    func testBeginPutsWindowOpenAndRestorePicksUpPersistedState() {
        let clock = MutableClock()
        let state = InMemoryBatchState()
        let tracker = BatchTracker(state: state, now: { clock.now })

        tracker.begin(Array(Puzzle.samples.prefix(1)))
        XCTAssertTrue(tracker.isWithinWindow)

        // A "relaunch": a fresh tracker over the same persisted state.
        let relaunched = BatchTracker(state: state, now: { clock.now })
        relaunched.restore()
        XCTAssertTrue(relaunched.isWithinWindow)
        XCTAssertEqual(relaunched.activePuzzleIDs(), Puzzle.samples.prefix(1).map(\.id))
    }

    @MainActor
    func testWindowExpiresAtExactlyDurationWithoutSleeping() {
        let clock = MutableClock()
        let state = InMemoryBatchState()
        let tracker = BatchTracker(state: state, now: { clock.now })

        tracker.begin(Array(Puzzle.samples.prefix(1)))
        // BatchPolicy.batchDuration is 5 minutes in Debug; advance past it.
        clock.advance(BatchPolicy.batchDuration)
        tracker.restore()
        XCTAssertFalse(tracker.isWithinWindow, "the window is closed after the full duration")
    }

    @MainActor
    func testCurrentPuzzlesResolvesActiveIDsAgainstTheLibrary() {
        let clock = MutableClock()
        let tracker = BatchTracker(state: InMemoryBatchState(), now: { clock.now })
        tracker.begin(Array(Puzzle.samples.prefix(2)))
        let resolved = tracker.currentPuzzles(from: Puzzle.samples)
        XCTAssertEqual(resolved.map(\.id), Array(Puzzle.samples.prefix(2).map(\.id)))
    }
}
