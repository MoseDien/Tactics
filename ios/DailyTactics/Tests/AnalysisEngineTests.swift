import XCTest
@testable import DailyTactics

final class AnalysisEngineTests: XCTestCase {
    private func position(_ fen: String) throws -> Analysis.Position {
        try Analysis.Position(fen: fen)
    }

    private func move(_ uci: String) -> Analysis.Move {
        let from = Analysis.Square(notation: String(uci.prefix(2)))!
        let to = Analysis.Square(notation: String(uci.dropFirst(2).prefix(2)))!
        let promotion: Analysis.PieceKind?
        if uci.count == 5 {
            switch uci.last {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: promotion = nil
            }
        } else {
            promotion = nil
        }
        return Analysis.Move(from: from, to: to, promotion: promotion)
    }

    // MARK: - Perft

    func testPerftStartPosition() throws {
        let board = try position(Analysis.Position.startFEN)
        XCTAssertEqual(board.perft(1), 20)
        XCTAssertEqual(board.perft(2), 400)
        XCTAssertEqual(board.perft(3), 8_902)
        XCTAssertEqual(board.perft(4), 197_281)
    }

    func testPerftKiwipete() throws {
        let board = try position("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        XCTAssertEqual(board.perft(1), 48)
        XCTAssertEqual(board.perft(2), 2_039)
    }

    func testPerftPositionThreeEnPassantHeavy() throws {
        let board = try position("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(board.perft(1), 14)
        XCTAssertEqual(board.perft(2), 191)
        XCTAssertEqual(board.perft(3), 2_812)
    }

    func testPerftPositionFourPromotionHeavy() throws {
        let board = try position("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
        XCTAssertEqual(board.perft(1), 6)
        XCTAssertEqual(board.perft(2), 264)
    }

    // MARK: - FEN

    func testFENRoundTrip() throws {
        let fens = [
            Analysis.Position.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 0 1",
            "4k3/8/8/8/8/8/8/R3K2R b KQ - 3 42",
            "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        ]
        for fen in fens {
            XCTAssertEqual(try position(fen).fen, fen, "round-trip must preserve \(fen)")
        }
    }

    func testMalformedFENThrows() {
        XCTAssertThrowsError(try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1"))
        XCTAssertThrowsError(try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1"))
        XCTAssertThrowsError(try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQxq - 0 1"))
        XCTAssertThrowsError(try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e9 0 1"))
        XCTAssertThrowsError(try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPPP/RNBQKBNR w KQkq - 0 1"))
    }

    // MARK: - Pins

    func testAbsolutelyPinnedKnightHasNoMoves() throws {
        let board = try position("4k3/4r3/8/8/8/4N3/8/4K3 w - - 0 1")
        let knight = Analysis.Square(notation: "e3")!
        XCTAssertTrue(board.legalMoves(from: knight).isEmpty)
    }

    func testPinnedRokMayOnlySlideAlongThePin() throws {
        let board = try position("4k3/4r3/8/8/8/4R3/8/4K3 w - - 0 1")
        let rook = Analysis.Square(notation: "e3")!
        let destinations = Set(board.legalMoves(from: rook).map(\.to.notation))
        XCTAssertEqual(destinations, ["e2", "e4", "e5", "e6", "e7"], "a pinned rook slides — and captures the pinner — along the file")
    }

    // MARK: - Castling

    func testCastlingBothSidesAndRightsExpiry() throws {
        let board = try position("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        let king = Analysis.Square(notation: "e1")!
        let destinations = Set(board.legalMoves(from: king).map(\.to.notation))
        XCTAssertTrue(destinations.contains("g1"))
        XCTAssertTrue(destinations.contains("c1"))

        let kingSide = board.applying(move("e1g1"))
        XCTAssertEqual(kingSide[Analysis.Square(notation: "f1")!]?.kind, .rook)
        XCTAssertEqual(kingSide.fen.split(separator: " ")[2], "-", "king move clears both rights")

        let queenSide = board.applying(move("e1c1"))
        XCTAssertEqual(queenSide[Analysis.Square(notation: "d1")!]?.kind, .rook)

        let rookMoved = board.applying(move("a1a2"))
        XCTAssertEqual(rookMoved.fen.split(separator: " ")[2], "K", "moving the a1 rook drops only queenside")
    }

    func testCastlingThroughOrWhileInCheckIsRejected() throws {
        let throughCheck = try position("4k3/8/8/8/8/5r2/8/R3K2R w KQ - 0 1")
        let king = Analysis.Square(notation: "e1")!
        let throughDestinations = Set(throughCheck.legalMoves(from: king).map(\.to.notation))
        XCTAssertFalse(throughDestinations.contains("g1"), "f1 is attacked")
        XCTAssertTrue(throughDestinations.contains("c1"))

        let inCheck = try position("4k3/8/8/8/8/4r3/8/R3K2R w KQ - 0 1")
        let checkedDestinations = Set(inCheck.legalMoves(from: king).map(\.to.notation))
        XCTAssertFalse(checkedDestinations.contains("g1"))
        XCTAssertFalse(checkedDestinations.contains("c1"))
    }

    func testCapturingARookOnItsHomeCornerClearsThatRight() throws {
        let board = try position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let next = board.applying(move("a1a8"))
        XCTAssertEqual(next.fen.split(separator: " ")[2], "Kk", "the capture drops white queenside (mover left a1) and black queenside (rook taken on a8)")
    }

    // MARK: - En passant

    func testEnPassantCaptureRemovesThePushedPawn() throws {
        let board = try position("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let pawn = Analysis.Square(notation: "d4")!
        let capture = move("d4e3")
        XCTAssertTrue(board.legalMoves(from: pawn).contains(capture))

        let next = board.applying(capture)
        XCTAssertNil(next[Analysis.Square(notation: "e4")!], "the captured pawn disappears from e4")
        XCTAssertEqual(next[Analysis.Square(notation: "e3")!]?.kind, .pawn)
        XCTAssertEqual(next.fen.split(separator: " ")[3], "-", "the EP target expires after the capture")
    }

    func testEnPassantTargetExpiresAfterOneUnrelatedMove() throws {
        let board = try position("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let afterKnight = board.applying(move("b8c6"))
        let pawn = Analysis.Square(notation: "d4")!
        XCTAssertFalse(afterKnight.legalMoves(from: pawn).contains(move("d4e3")))
    }

    func testPinnedEnPassantCaptureIsIllegal() throws {
        let board = try position("8/8/8/K1pP3r/8/8/8/7k w - c6 0 1")
        let pawn = Analysis.Square(notation: "d5")!
        XCTAssertFalse(board.legalMoves(from: pawn).contains(move("d5c6")), "the capture opens the 5th rank to the rook")
        XCTAssertTrue(board.legalMoves(from: pawn).contains(move("d5d6")), "the push stays legal")
    }

    // MARK: - Promotion

    func testPromotionGeneratesExactlyFourPieces() throws {
        let board = try position("8/P6k/8/8/8/8/8/K7 w - - 0 1")
        let pawn = Analysis.Square(notation: "a7")!
        let promotions = board.legalMoves(from: pawn)
        XCTAssertEqual(promotions.count, 4)
        XCTAssertEqual(Set(promotions.compactMap(\.promotion)), [.queen, .rook, .bishop, .knight])

        XCTAssertEqual(board.applying(move("a7a8q"))[Analysis.Square(notation: "a8")!]?
            .kind, .queen)
        XCTAssertEqual(board.applying(move("a7a8n"))[Analysis.Square(notation: "a8")!]?
            .kind, .knight)
    }

    func testPromotionDeliveringCheck() throws {
        let board = try position("5k2/P7/8/8/8/8/8/4K3 w - - 0 1")
        let next = board.applying(move("a7a8q"))
        XCTAssertEqual(Analysis.Status.of(next), .check)
    }

    // MARK: - Status

    func testFoolsMateIsCheckmateForBlack() throws {
        var game = Analysis.Game.start()
        game.play(move("f2f3"))
        game.play(move("e7e5"))
        game.play(move("g2g4"))
        game.play(move("d8h4"))
        XCTAssertEqual(game.status, .checkmate(winner: .black))
    }

    func testStalemateDetection() throws {
        let board = try position("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(Analysis.Status.of(board), .stalemate)
    }

    func testCheckDetectionKeepsMovesAvailable() throws {
        let board = try position("4k3/8/8/8/8/8/4q3/4K3 w - - 0 1")
        XCTAssertEqual(Analysis.Status.of(board), .check)
        XCTAssertFalse(board.legalMoves(for: .white).isEmpty)
    }
}

/// Counts leaf nodes; depth 1 returns the bulk count, as standard perft does.
private extension Analysis.Position {
    func perft(_ depth: Int) -> Int {
        guard depth > 0 else { return 1 }
        let moves = legalMoves(for: activeColor)
        if depth == 1 { return moves.count }
        var nodes = 0
        for move in moves {
            nodes += applying(move).perft(depth - 1)
        }
        return nodes
    }
}
