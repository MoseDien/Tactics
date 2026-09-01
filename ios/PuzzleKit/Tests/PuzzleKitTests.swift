import XCTest
import ChessCore
import PuzzleKit
@testable import PuzzleKit

final class PuzzleKitTests: XCTestCase {
    func testExpectedFirstMoveIsRecognized() throws {
        var session = try PuzzleSession(puzzle: Puzzle.samples[0])

        XCTAssertEqual(session.state, .opponentMoving)
        XCTAssertEqual(session.expectedMove?.uci, Puzzle.samples[0].moves[0])
        XCTAssertEqual(session.userColor, .black)

        try session.applyOpponentMove()

        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.expectedMove?.uci, Puzzle.samples[0].moves[1])
    }

    func testWrongMoveIsRejectedButRetriableAndLeavesBoardUnchanged() throws {
        var session = try PuzzleSession(puzzle: Puzzle.samples[0])
        try session.applyOpponentMove()
        let originalBoard = session.board
        let expectedMove = try XCTUnwrap(session.expectedMove)
        let wrongTarget = Square(notation: expectedMove.to.notation == "e7" ? "e6" : "e7")!

        try session.submitUserMove(ChessMove(from: expectedMove.from, to: wrongTarget))

        // Wrong move is rejected but the user may retry — the view layer records
        // the failure separately.
        XCTAssertEqual(session.state, .incorrectMove)
        XCTAssertEqual(session.board, originalBoard)

        session.resumeAfterIncorrectMove()
        XCTAssertEqual(session.state, .waitingForMove)
    }

    func testCompleteLineReachesSolvedAndRestartRestoresPuzzle() throws {
        var session = try PuzzleSession(puzzle: Puzzle.samples[0])
        let firstUserMove = try XCTUnwrap(ChessMove(uci: Puzzle.samples[0].moves[1]))
        let finalUserMove = try XCTUnwrap(ChessMove(uci: Puzzle.samples[0].moves[3]))

        try session.applyOpponentMove()
        XCTAssertEqual(session.lastMove?.uci, Puzzle.samples[0].moves[0])

        try session.submitUserMove(firstUserMove)
        XCTAssertEqual(session.state, .opponentMoving)

        try session.applyOpponentMove()
        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.lastMove?.uci, Puzzle.samples[0].moves[2])

        try session.submitUserMove(finalUserMove)
        XCTAssertEqual(session.state, .solved)
        XCTAssertEqual(session.lastMove?.uci, Puzzle.samples[0].moves[3])

        try session.restart()
        XCTAssertEqual(session.state, .opponentMoving)
        XCTAssertEqual(session.currentMoveIndex, 0)
        XCTAssertEqual(session.board.sideToMove, .white)
        XCTAssertNil(session.lastMove)
    }

    func testFourPlyLichessLineAlternatesMachineAndPlayer() throws {
        let puzzle = Puzzle(
            id: "machine-first",
            fen: "6k1/8/8/3N4/8/8/8/4r1K1 b - - 0 1",
            moves: ["e1d1", "d5c3", "d1c2", "c3e2"],
            rating: nil,
            themes: [.fork]
        )
        var session = try PuzzleSession(puzzle: puzzle)

        XCTAssertEqual(session.state, .opponentMoving)
        try session.applyOpponentMove()
        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.expectedMove?.uci, "d5c3")

        try session.submitUserMove(ChessMove(uci: "d5c3")!)
        XCTAssertEqual(session.state, .opponentMoving)
        try session.applyOpponentMove()
        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.expectedMove?.uci, "c3e2")

        try session.submitUserMove(ChessMove(uci: "c3e2")!)
        XCTAssertEqual(session.state, .solved)
    }

    // MARK: - Bundled puzzle data

    func testAllSamplesArePlayableToSolvedWithUniqueIDs() throws {
        var seenIDs = Set<String>()
        for puzzle in Puzzle.samples {
            XCTAssertFalse(seenIDs.contains(puzzle.id), "Duplicate puzzle id: \(puzzle.id)")
            seenIDs.insert(puzzle.id)

            var session = try PuzzleSession(puzzle: puzzle)
            while session.canStepForward {
                try session.stepForward()
            }
            XCTAssertEqual(session.state, .solved, "Puzzle \(puzzle.id) did not reach solved")
        }
    }

    // MARK: - Legal move validation

    func testPuzzleDecodesFromJSON() throws {
        let json = #"""
        [{"id":"abc","fen":"4k3/8/8/8/8/8/8/4K3 w - - 0 1","moves":["e1e2"],"rating":1500,
          "ratingDeviation":80,"popularity":90,"playCount":1234,
          "themes":["fork","endgame"],"gameUrl":"https://lichess.org/abc",
          "openingTags":["Italian Game"]}]
        """#.data(using: .utf8)!
        let puzzles = try JSONDecoder().decode([Puzzle].self, from: json)
        XCTAssertEqual(puzzles.count, 1)
        XCTAssertEqual(puzzles[0].id, "abc")
        XCTAssertEqual(puzzles[0].rating, 1500)
        XCTAssertEqual(puzzles[0].themes, [.fork, .endgame])
        // Full Lichess metadata round-trips.
        XCTAssertEqual(puzzles[0].ratingDeviation, 80)
        XCTAssertEqual(puzzles[0].popularity, 90)
        XCTAssertEqual(puzzles[0].playCount, 1234)
        XCTAssertEqual(puzzles[0].gameUrl, "https://lichess.org/abc")
        XCTAssertEqual(puzzles[0].openingTags, ["Italian Game"])
    }

    func testPuzzleDecodesWithoutOptionalMetadata() throws {
        // Older datasets omit the metadata fields; they decode to nil.
        let json = #"""
        [{"id":"x","fen":"4k3/8/8/8/8/8/8/4K3 w - - 0 1","moves":["e1e2"],"rating":null,"themes":[]}]
        """#.data(using: .utf8)!
        let puzzle = try JSONDecoder().decode([Puzzle].self, from: json)[0]
        XCTAssertNil(puzzle.ratingDeviation)
        XCTAssertNil(puzzle.gameUrl)
        XCTAssertNil(puzzle.openingTags)
    }

    @MainActor

    func testPuzzleRatingRewardsHarderCleanSolvesMore() {
        let calculator = PuzzleRatingCalculator()

        XCTAssertGreaterThan(calculator.change(userRating: 1500, puzzleRating: 2200, solved: true),
                             calculator.change(userRating: 1500, puzzleRating: 1000, solved: true))
        XCTAssertLessThan(calculator.change(userRating: 1500, puzzleRating: 2200, solved: false), 0)
        XCTAssertGreaterThan(calculator.expectedScore(userRating: 1500, puzzleRating: 1000), 0.5)
    }

    func testRatingChangeForcesMinimumMagnitudeOfOne() {
        let calculator = PuzzleRatingCalculator()
        // An equal rating with a solve rounds to 32*(1-0.5)=16; the forced ±1
        // only shows at extreme gaps where 32*(1-e) rounds to 0.
        let hugeSolve = calculator.change(userRating: 3000, puzzleRating: 400, solved: true)
        XCTAssertGreaterThanOrEqual(hugeSolve, 1, "a solve must never yield a zero/negative delta")
        let hugeLoss = calculator.change(userRating: 400, puzzleRating: 3000, solved: false)
        XCTAssertLessThanOrEqual(hugeLoss, -1, "a loss must never yield a zero/positive delta")
    }

    @MainActor

    func testBatchPolicyDuration() {
        // Tests build in Debug: the window is shortened to 5 minutes so the
        // batch cycle is exercisable by hand. Release uses the full cadence.
        #if DEBUG
        XCTAssertEqual(BatchPolicy.batchDuration, 5 * 60)
        #else
        XCTAssertEqual(BatchPolicy.batchDuration, 8 * 60 * 60)
        #endif
        XCTAssertEqual(BatchPolicy.puzzleCount, 5)
    }

    func testBatchLookupToleratesDuplicateLibraryIDs() {
        let puzzle = Puzzle.samples[0]
        let library = [puzzle, puzzle]  // duplicate id in the library
        // Must not trap despite the duplicated id.
        XCTAssertEqual(BatchLookup.puzzles(withIDs: [puzzle.id], in: library).count, 1)
    }
}
