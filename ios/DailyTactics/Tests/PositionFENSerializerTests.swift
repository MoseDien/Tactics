import XCTest
import ChessCore
import PuzzleKit
@testable import DailyTactics

final class PositionFENSerializerTests: XCTestCase {
    /// Serialize → reparse through ChessCore's own parser: every readable
    /// state field must survive the round trip.
    private func assertRoundTrips(_ fen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let board = try Board(fen: fen)
        let serialized = PositionFENSerializer.fen(from: board)
        let reparsed = try Board(fen: serialized)
        XCTAssertEqual(reparsed.pieces, board.pieces, file: file, line: line)
        XCTAssertEqual(reparsed.sideToMove, board.sideToMove, file: file, line: line)
        XCTAssertEqual(reparsed.castlingRights, board.castlingRights, file: file, line: line)
        XCTAssertEqual(reparsed.enPassantTarget, board.enPassantTarget, file: file, line: line)
    }

    func testRoundTripsCanonicalPositions() throws {
        try assertRoundTrips("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        try assertRoundTrips("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        try assertRoundTrips("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        try assertRoundTrips("4k3/8/8/8/8/8/8/R3K2R b KQ - 3 42")
        try assertRoundTrips("r3k2r/PPP5/8/8/8/8/5ppp/R3K2R w KQkq - 0 1")
    }

    func testRoundTripsEverySamplePuzzleFEN() throws {
        for puzzle in Puzzle.samples {
            try assertRoundTrips(puzzle.fen)
        }
    }

    func testRightsFieldFormatting() throws {
        let partial = try Board(fen: "r3k2r/8/8/8/8/8/8/R3K2R w Kq - 0 1")
        XCTAssertEqual(PositionFENSerializer.fen(from: partial).split(separator: " ")[2], "Kq")

        let none = try Board(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(PositionFENSerializer.fen(from: none).split(separator: " ")[2], "-")
    }

    func testActiveColorAndEnPassantFields() throws {
        let afterDoublePush = try Board(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let fields = PositionFENSerializer.fen(from: afterDoublePush).split(separator: " ")
        XCTAssertEqual(fields[1], "b")
        XCTAssertEqual(fields[3], "e3")
    }

    func testAnalysisSeedResetsPuzzleThenAppliesMachineOpeningMove() throws {
        let puzzle = Puzzle.samples[0]
        var expected = try PuzzleSession(puzzle: puzzle)
        try expected.applyOpponentMove()

        let analysisBoard = try Board(fen: PositionFENSerializer.analysisFEN(for: puzzle))
        XCTAssertEqual(analysisBoard.pieces, expected.board.pieces)
        XCTAssertEqual(analysisBoard.sideToMove, expected.board.sideToMove)
    }
}
