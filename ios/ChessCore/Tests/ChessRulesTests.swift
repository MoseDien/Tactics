import XCTest
@testable import ChessCore

final class ChessRulesTests: XCTestCase {
    func testFENParsesPiecesAndSideToMove() throws {
        // Same position as Puzzle.samples[0], inlined so ChessCore tests
        // don't depend on PuzzleKit.
        let board = try Board(fen: "r3k2r/p1pp1p1p/b1p3p1/3nP3/1bP5/NP6/P3QPPP/R3KB1R w KQkq - 1")

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

    func testLegalMovesRespectPieceShapesAndBlocking() throws {
        let rookBoard = try Board(fen: "7k/8/8/8/8/8/8/R3K3 w - - 0 1")
        XCTAssertTrue(rookBoard.isLegal(ChessMove(uci: "a1a7")!, for: .white))    // rook straight, clear
        XCTAssertFalse(rookBoard.isLegal(ChessMove(uci: "a1b2")!, for: .white))   // diagonal — not a rook move
        XCTAssertTrue(rookBoard.isLegal(ChessMove(uci: "e1d1")!, for: .white))    // king one square
        XCTAssertFalse(rookBoard.isLegal(ChessMove(uci: "e1c1")!, for: .white))   // king two squares

        let bishopBoard = try Board(fen: "7k/8/8/8/8/4P3/8/2B1K3 w - - 0 1")
        XCTAssertTrue(bishopBoard.isLegal(ChessMove(uci: "c1d2")!, for: .white))  // one step diagonal
        XCTAssertFalse(bishopBoard.isLegal(ChessMove(uci: "c1g5")!, for: .white)) // blocked by the e3 pawn

        let knightBoard = try Board(fen: "7k/8/8/8/8/2P5/8/1N2K3 w - - 0 1")
        XCTAssertTrue(knightBoard.isLegal(ChessMove(uci: "b1a3")!, for: .white))  // L-move to empty
        XCTAssertFalse(knightBoard.isLegal(ChessMove(uci: "b1c3")!, for: .white)) // L-move onto own pawn

        let emptyBoard = try Board(fen: "7k/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertFalse(emptyBoard.isLegal(ChessMove(uci: "a1a2")!, for: .white))  // no piece on origin
    }

    func testPawnPushAndCapture() throws {
        let board = try Board(fen: "7k/8/8/8/8/3p4/4P3/4K3 w - - 0 1")
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e2e4")!, for: .white))   // two-square start push
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e2e3")!, for: .white))   // one-square push
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e2d3")!, for: .white))   // diagonal capture
        XCTAssertFalse(board.isLegal(ChessMove(uci: "e2f3")!, for: .white))  // diagonal to empty — no capture
    }

    // MARK: - Full legality: check, pin, castling, en passant, promotion

    func testKingCannotMoveIntoCheck() throws {
        // Black rook on e-file controls e2/e3: the white king may not step up.
        let board = try Board(fen: "4k3/8/8/8/4r3/8/8/4K3 w - - 0 1")
        XCTAssertFalse(board.isLegal(ChessMove(uci: "e1e2")!, for: .white))
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e1d1")!, for: .white))
    }

    func testPinnedPieceCannotExposeItsKing() throws {
        // The rook on e8 pins the e2 pawn against Ke1. Any move that leaves
        // the e-file (a diagonal capture) would expose the king: rejected.
        let board = try Board(fen: "4r3/8/8/8/8/3p4/4P3/4K3 w - - 0 1")
        XCTAssertFalse(board.isLegal(ChessMove(uci: "e2d3")!, for: .white))
        // Pushing along the pin line keeps the king shielded: legal.
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e2e3")!, for: .white))
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e2e4")!, for: .white))
    }

    func testCastlingLegality() throws {
        // Rights present, path clear, no attacks: legal.
        let legal = try Board(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertTrue(legal.isLegal(ChessMove(uci: "e1g1")!, for: .white))
        XCTAssertTrue(legal.isLegal(ChessMove(uci: "e1c1")!, for: .white))

        // No rights in the FEN: illegal even with the path clear.
        let noRights = try Board(fen: "4k3/8/8/8/8/8/8/R3K2R w - - 0 1")
        XCTAssertFalse(noRights.isLegal(ChessMove(uci: "e1g1")!, for: .white))

        // King in check may not castle out of it.
        let checked = try Board(fen: "4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1")
        XCTAssertFalse(checked.isLegal(ChessMove(uci: "e1g1")!, for: .white))

        // Passing through an attacked square is illegal.
        let throughAttacked = try Board(fen: "4k3/8/8/8/8/5r2/8/R3K2R w KQ - 0 1")
        XCTAssertFalse(throughAttacked.isLegal(ChessMove(uci: "e1g1")!, for: .white))
    }

    func testEnPassantIsLegalWhenTargetMatches() throws {
        // FEN says d6 is the en-passant target; the diagonal shape is otherwise
        // an illegal capture onto an empty square.
        let board = try Board(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        XCTAssertTrue(board.isLegal(ChessMove(uci: "e5d6")!, for: .white))
        // Without the en-passant field the same shape is illegal.
        let plain = try Board(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")
        XCTAssertFalse(plain.isLegal(ChessMove(uci: "e5d6")!, for: .white))
    }

    func testPromotionRequirementInIsLegal() throws {
        // Pawn to last rank without a promotion piece: rejected.
        let board = try Board(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertFalse(board.isLegal(ChessMove(uci: "a7a8")!, for: .white))
        XCTAssertTrue(board.isLegal(ChessMove(uci: "a7a8q")!, for: .white))
        XCTAssertTrue(board.isLegal(ChessMove(uci: "a7a8n")!, for: .white))
        // A promotion suffix on a non-pawn move is rejected.
        XCTAssertFalse(board.isLegal(ChessMove(uci: "e1e2q")!, for: .white))
    }

    func testApplyUpdatesSideToMoveAndEnPassantContext() throws {
        var board = try Board(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertTrue(board.apply(ChessMove(uci: "e2e4")!))
        XCTAssertEqual(board.sideToMove, .black, "apply must toggle the recorded turn")
        XCTAssertEqual(board.enPassantTarget?.notation, "e3")
        XCTAssertNil(board.pieces[Square(notation: "e2")!])
    }

    func testEnPassantApplyOnlyRemovesAnEnemyPawn() throws {
        // Regression for the destructive heuristic: a pawn moving diagonally to
        // an empty square must not remove anything unless an enemy pawn stands
        // beside its origin. b5→a6 with a friendly piece left on b4 must leave
        // the board otherwise intact.
        var board = try Board(fen: "4k3/8/8/1P6/8/8/8/4K3 w - a6 0 1")
        XCTAssertTrue(board.apply(ChessMove(uci: "b5a6")!))
        XCTAssertNotNil(board.pieces[Square(notation: "a6")!], "the pawn lands on a6")
        XCTAssertNil(board.pieces[Square(notation: "b4")!], "no friendly piece is deleted")
    }

    func testFENParsesCastlingAndEnPassantFields() throws {
        let board = try Board(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq e3 12 33")
        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertEqual(board.enPassantTarget?.notation, "e3")
    }

    func testFENRejectsNonASCIIDigitsAndBadRanks() throws {
        XCTAssertThrowsError(try Board(fen: "٣٣３٣٣٣٣/8/8/8/8/8/8/4K3 w - - 0 1"))
        // "44" is two digit runs in one rank (FEN requires a single digit 8).
        XCTAssertThrowsError(try Board(fen: "44/8/8/8/8/8/8/4K3 w - - 0 1"),
                             "multi-digit rank runs must not pass as skips")
        XCTAssertThrowsError(try Board(fen: "8/8/8/8/8/8/8/4K3"))              // missing side-to-move
    }

    // MARK: - Special moves (castling / en passant) in apply

    func testCastlingAlsoRelocatesTheRook() throws {
        var board = try Board(fen: "4k3/8/8/8/8/8/8/4K2R w - - 0 1")
        XCTAssertTrue(board.apply(ChessMove(uci: "e1g1")!))
        XCTAssertNotNil(board.pieces[Square(notation: "g1")!])  // king on g1
        XCTAssertNotNil(board.pieces[Square(notation: "f1")!])  // rook on f1
        XCTAssertNil(board.pieces[Square(notation: "e1")!])
        XCTAssertNil(board.pieces[Square(notation: "h1")!])
    }

    func testEnPassantRemovesTheCapturedPawn() throws {
        var board = try Board(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        XCTAssertTrue(board.apply(ChessMove(uci: "e5d6")!))
        XCTAssertNotNil(board.pieces[Square(notation: "d6")!])  // white pawn lands on d6
        XCTAssertNil(board.pieces[Square(notation: "d5")!])     // captured black pawn gone
        XCTAssertNil(board.pieces[Square(notation: "e5")!])     // origin vacated
    }

    // MARK: - Puzzle decoding & progress persistence
}
