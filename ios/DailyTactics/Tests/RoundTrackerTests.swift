import XCTest
import PuzzleKit
@testable import DailyTactics

final class RoundTrackerTests: XCTestCase {
    @MainActor
    func testBeginPutsWindowOpenAndRestorePicksUpPersistedState() {
        let clock = MutableClock()
        let state = InMemoryRoundState()
        let tracker = RoundTracker(state: state, now: { clock.now })

        tracker.begin(Array(Puzzle.samples.prefix(1)))
        XCTAssertTrue(tracker.isWithinWindow)

        // A "relaunch": a fresh tracker over the same persisted state.
        let relaunched = RoundTracker(state: state, now: { clock.now })
        relaunched.restore()
        XCTAssertTrue(relaunched.isWithinWindow)
        XCTAssertEqual(relaunched.activePuzzleIDs(), Puzzle.samples.prefix(1).map(\.id))
    }

    @MainActor
    func testWindowExpiresAtExactlyDurationWithoutSleeping() {
        let clock = MutableClock()
        let state = InMemoryRoundState()
        let tracker = RoundTracker(state: state, now: { clock.now })

        tracker.begin(Array(Puzzle.samples.prefix(1)))
        // RoundPolicy.roundDuration is 5 minutes in Debug; advance past it.
        clock.advance(RoundPolicy.roundDuration)
        tracker.restore()
        XCTAssertFalse(tracker.isWithinWindow, "the window is closed after the full duration")
    }

    @MainActor
    func testCurrentPuzzlesResolvesActiveIDsAgainstTheLibrary() {
        let clock = MutableClock()
        let tracker = RoundTracker(state: InMemoryRoundState(), now: { clock.now })
        tracker.begin(Array(Puzzle.samples.prefix(2)))
        let resolved = tracker.currentPuzzles(from: Puzzle.samples)
        XCTAssertEqual(resolved.map(\.id), Array(Puzzle.samples.prefix(2).map(\.id)))
    }
}
