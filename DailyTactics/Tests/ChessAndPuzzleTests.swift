import XCTest
@testable import DailyTactics

final class ChessAndPuzzleTests: XCTestCase {
    func testFENParsesPiecesAndSideToMove() throws {
        let board = try Board(fen: Puzzle.sample.fen)

        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertEqual(board.pieces[Square(notation: "e1")!], Piece(color: .white, kind: .king))
        XCTAssertEqual(board.pieces[Square(notation: "d5")!], Piece(color: .black, kind: .knight))
        XCTAssertEqual(board.pieces[Square(notation: "a8")!], Piece(color: .black, kind: .rook))
    }

    func testSquareAndUCIRoundTrip() {
        XCTAssertEqual(Square(notation: "e8")?.notation, "e8")
        XCTAssertEqual(ChessMove(uci: "h5e8")?.uci, "h5e8")
        XCTAssertEqual(ChessMove(uci: "a7a8q")?.promotion, .queen)
        XCTAssertNil(ChessMove(uci: "not-a-move"))
    }

    func testExpectedFirstMoveIsRecognized() throws {
        var session = try PuzzleSession(puzzle: .sample)

        XCTAssertEqual(session.state, .opponentMoving)
        XCTAssertEqual(session.expectedMove?.uci, Puzzle.sample.moves[0])
        XCTAssertEqual(session.userColor, .black)

        try session.applyOpponentMove()

        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.expectedMove?.uci, Puzzle.sample.moves[1])
    }

    func testIncorrectMoveIsRejectedWithoutChangingBoard() throws {
        var session = try PuzzleSession(puzzle: .sample)
        try session.applyOpponentMove()
        let originalBoard = session.board
        let expectedMove = try XCTUnwrap(session.expectedMove)
        let wrongTarget = Square(notation: expectedMove.to.notation == "e7" ? "e6" : "e7")!

        try session.submitUserMove(ChessMove(from: expectedMove.from, to: wrongTarget))

        XCTAssertEqual(session.state, .incorrectMove)
        XCTAssertEqual(session.board, originalBoard)
    }

    func testCompleteLineReachesSolvedAndRestartRestoresPuzzle() throws {
        var session = try PuzzleSession(puzzle: .sample)
        let firstUserMove = try XCTUnwrap(ChessMove(uci: Puzzle.sample.moves[1]))
        let finalUserMove = try XCTUnwrap(ChessMove(uci: Puzzle.sample.moves[3]))

        try session.applyOpponentMove()
        XCTAssertEqual(session.lastMove?.uci, Puzzle.sample.moves[0])

        try session.submitUserMove(firstUserMove)
        XCTAssertEqual(session.state, .opponentMoving)

        try session.applyOpponentMove()
        XCTAssertEqual(session.state, .waitingForMove)
        XCTAssertEqual(session.lastMove?.uci, Puzzle.sample.moves[2])

        try session.submitUserMove(finalUserMove)
        XCTAssertEqual(session.state, .solved)
        XCTAssertEqual(session.lastMove?.uci, Puzzle.sample.moves[3])

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
}
