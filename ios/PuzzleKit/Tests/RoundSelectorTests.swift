import XCTest
import PuzzleKit

final class RoundSelectorTests: XCTestCase {
    private let library = (0..<20).map { i in
        Puzzle(id: "p\(i)", fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2"], rating: 1000 + i * 50, themes: [])
    }

    func testSelectExcludesAttemptedAndExcluded() {
        let selector = RoundSelector(shuffle: { $0 })
        let picked = selector.select(
            library: library, attempted: ["p0", "p1"], difficulty: .medium,
            userRating: 1500, count: 5, excluding: ["p2"]
        )
        XCTAssertEqual(picked.count, 5)
        let ids = Set(picked.map(\.id))
        XCTAssertFalse(ids.contains("p0"))
        XCTAssertFalse(ids.contains("p1"))
        XCTAssertFalse(ids.contains("p2"), "the previous batch's puzzles are excluded")
    }

    func testEasyBandsBelowUserRatingPlus200() {
        let selector = RoundSelector(shuffle: { $0 })
        let picked = selector.select(library: library, attempted: [], difficulty: .easy, userRating: 1500, count: 8)
        XCTAssertTrue(picked.allSatisfy { ($0.rating ?? 0) <= 1700 })
    }

    func testHardBandsAboveUserRatingMinus200() {
        let selector = RoundSelector(shuffle: { $0 })
        let picked = selector.select(library: library, attempted: [], difficulty: .hard, userRating: 1500, count: 8)
        XCTAssertTrue(picked.allSatisfy { ($0.rating ?? .max) >= 1300 })
    }

    func testFallsBackToWholeLibraryWhenUnattemptedInsufficient() {
        let selector = RoundSelector(shuffle: { $0 })
        let almostAll = Set((0..<18).map { "p\($0)" })
        let picked = selector.select(library: library, attempted: almostAll, difficulty: .medium, userRating: 1500, count: 5)
        XCTAssertEqual(picked.count, 5, "falls back to random-over-all so a round is always available")
    }

    func testEmptyLibraryReturnsEmpty() {
        let selector = RoundSelector()
        XCTAssertTrue(selector.select(library: [], attempted: [], difficulty: .medium, userRating: 1500, count: 5).isEmpty)
    }

    func testFewerThanCountReturnsWhatExists() {
        let selector = RoundSelector(shuffle: { $0 })
        let picked = selector.select(library: Array(library.prefix(3)), attempted: [], difficulty: .medium, userRating: 1500, count: 5)
        XCTAssertEqual(picked.count, 3)
    }

    func testInjectedShuffleIsDeterministic() {
        // Reverse-order shuffle: prefix(count) must pick deterministically.
        let selector = RoundSelector(shuffle: { Array($0.reversed()) })
        let a = selector.select(library: library, attempted: [], difficulty: .medium, userRating: 1500, count: 3)
        let b = selector.select(library: library, attempted: [], difficulty: .medium, userRating: 1500, count: 3)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.map(\.id), ["p19", "p18", "p17"])
    }
}

final class BatchWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testWindowBoundaries() {
        let window = BatchWindow(startedAt: start, duration: 100)
        XCTAssertTrue(window.contains(start))
        XCTAssertTrue(window.contains(start + 99))
        XCTAssertFalse(window.contains(start + 100), "expiry is exclusive — a new batch may start")
        XCTAssertFalse(window.contains(start - 1))
    }

    func testSecondsRemainingSign() {
        let window = BatchWindow(startedAt: start, duration: 100)
        XCTAssertEqual(window.secondsRemaining(at: start), 100, accuracy: 0.001)
        XCTAssertLessThan(window.secondsRemaining(at: start + 150), 0, "negative once expired")
    }

    func testLookupToleratesDuplicateLibraryIDs() {
        let puzzle = library0
        let found = BatchLookup.puzzles(withIDs: [puzzle.id], in: [puzzle, puzzle])
        XCTAssertEqual(found.count, 1)
    }

    private var library0: Puzzle {
        Puzzle(id: "dup", fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2"], rating: nil, themes: [])
    }
}
