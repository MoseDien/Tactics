import XCTest
@testable import DailyTactics

final class AnalysisGameTests: XCTestCase {
    private func move(_ uci: String) -> Analysis.Move {
        let from = Analysis.Square(notation: String(uci.prefix(2)))!
        let to = Analysis.Square(notation: String(uci.dropFirst(2).prefix(2)))!
        return Analysis.Move(from: from, to: to)
    }

    private func square(_ notation: String) -> Analysis.Square {
        Analysis.Square(notation: notation)!
    }

    // MARK: - Game history

    func testUndoRestoresTheExactPosition() throws {
        var game = try Analysis.Game(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        let before = game.position
        game.play(move("e1g1"))
        XCTAssertEqual(game.lastMove?.to.notation, "g1")

        game.undo()
        XCTAssertEqual(game.position, before, "castling undo restores rights, rook, and side to move")
        XCTAssertFalse(game.canUndo, "the seed frame is the floor")
        game.undo()
        XCTAssertEqual(game.position, before, "undo past the seed is a no-op")
    }

    func testUndoAfterDoublePushClearsEnPassantTarget() throws {
        var game = Analysis.Game.start()
        game.play(move("e2e4"))
        XCTAssertEqual(game.position.enPassantTarget?.notation, "e3")
        game.undo()
        XCTAssertNil(game.position.enPassantTarget)
        XCTAssertEqual(game.moves.count, 0)
    }

    func testResetToSeed() throws {
        var game = Analysis.Game.start()
        game.play(move("e2e4"))
        game.play(move("e7e5"))
        let seed = game.positions[0]

        game.resetToSeed()
        XCTAssertEqual(game.positions, [seed])
        XCTAssertTrue(game.moves.isEmpty)
        XCTAssertFalse(game.canUndo)
    }

    // MARK: - Opening move history

    func testOpeningMoveIsHistoryFrameOne() throws {
        var game = try Analysis.Game(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        game.play(move("e2e4"))
        XCTAssertEqual(game.lastMove, move("e2e4"))
        XCTAssertTrue(game.canUndo, "the opener is rewindable")
        XCTAssertEqual(game.position.enPassantTarget?.notation, "e3")

        game.undo()
        XCTAssertNil(game.lastMove)
        XCTAssertFalse(game.canUndo)
    }

    // MARK: - Store tap machine

    @MainActor
    func testSelectingAPieceShowsOnlyItsLegalTargets() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        store.select(square("e2"))

        XCTAssertEqual(store.selectedSquare, square("e2"))
        XCTAssertEqual(store.legalTargets, Set([square("e3"), square("e4")]))
        XCTAssertFalse(store.legalTargets.contains(square("e1")), "the king is not a pawn target")
    }

    @MainActor
    func testSelectingEnemyOrEmptySquarePlaysNothing() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        store.select(square("e7"))  // black piece while white moves
        XCTAssertNil(store.selectedSquare)
        XCTAssertTrue(store.legalTargets.isEmpty)

        store.select(square("e4"))
        XCTAssertNil(store.selectedSquare)
        XCTAssertFalse(store.hasMoves)
    }

    @MainActor
    func testTappingALegalTargetPlaysAndAlternatesSides() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        store.select(square("e2"))
        store.select(square("e4"))

        XCTAssertTrue(store.hasMoves)
        XCTAssertEqual(store.lastMove?.to.notation, "e4")
        XCTAssertEqual(store.position.activeColor, .black)
        XCTAssertNil(store.selectedSquare)

        // Black now moves: both sides are playable.
        store.select(square("e7"))
        store.select(square("e5"))
        XCTAssertEqual(store.position.activeColor, .white)
    }

    @MainActor
    func testStorePublishesForwardAndUndoAnimationArrivals() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        store.select(square("e2"))
        store.select(square("e4"))

        XCTAssertEqual(store.animatedArrival, [square("e4"): square("e2")])
        XCTAssertEqual(store.moveRevision, 1)
        XCTAssertFalse(store.isUndoAnimation)

        store.undo()
        XCTAssertEqual(store.animatedArrival, [square("e2"): square("e4")])
        XCTAssertEqual(store.moveRevision, 2)
        XCTAssertTrue(store.isUndoAnimation)
    }

    @MainActor
    func testCastlingPublishesKingAndRookArrivals() {
        let store = AnalysisGameStore(seedFEN: "4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        store.select(square("e1"))
        store.select(square("g1"))

        XCTAssertEqual(store.animatedArrival[square("g1")], square("e1"))
        XCTAssertEqual(store.animatedArrival[square("f1")], square("h1"))
    }

    @MainActor
    func testTappingTheSelectedSquareDeselects() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        store.select(square("e2"))
        store.select(square("e2"))
        XCTAssertNil(store.selectedSquare)
        XCTAssertTrue(store.legalTargets.isEmpty)
    }

    @MainActor
    func testPromotionWaitsForAChoice() {
        let store = AnalysisGameStore(seedFEN: "8/P6k/8/8/8/8/8/K7 w - - 0 1")
        store.select(square("a7"))
        XCTAssertTrue(store.legalTargets.contains(square("a8")))

        store.select(square("a8"))
        XCTAssertNil(store.lastMove, "the move is held until a piece is chosen")
        XCTAssertEqual(store.pendingPromotion?.to, square("a8"))

        // A board tap while the picker is up cancels without playing.
        store.select(square("h2"))
        XCTAssertNil(store.pendingPromotion)
        XCTAssertNil(store.lastMove)

        store.select(square("a7"))
        store.select(square("a8"))
        store.choosePromotion(.queen)
        XCTAssertEqual(store.lastMove?.promotion, .queen)
        XCTAssertEqual(store.position[square("a8")]?.kind, .queen)
        XCTAssertEqual(store.position.activeColor, .black)
    }

    @MainActor
    func testBadSeedFallsBackToTheOpeningPosition() {
        let store = AnalysisGameStore(seedFEN: "not a fen")
        XCTAssertEqual(store.position.fen, Analysis.Position.startFEN)
        XCTAssertEqual(store.status, .playing)
    }

    @MainActor
    func testLoadOpensRawThenPlaysTheOpeningMove() async throws {
        let store = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: move("e2e4"),
            openingReplayDelay: .milliseconds(1)
        )
        XCTAssertTrue(store.game.moves.isEmpty, "the board opens on the raw position")
        XCTAssertNil(store.lastMove)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.lastMove, move("e2e4"), "the opener walks itself in")
        XCTAssertEqual(store.animatedArrival, [square("e4"): square("e2")], "the entry slides")
        XCTAssertFalse(store.isUndoAnimation)
    }

    @MainActor
    func testUndoLandsOnTheSetupFrameWithTheOpenerHighlighted() async throws {
        let opening = move("e2e4")
        let store = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: opening,
            openingReplayDelay: .milliseconds(1)
        )
        try await Task.sleep(for: .milliseconds(80))  // opener in

        store.select(square("a7"))
        store.select(square("a6"))
        XCTAssertEqual(store.lastMove, move("a7a6"), "a played move takes over the highlight")

        store.undo()
        XCTAssertEqual(store.lastMove, opening, "undo stops at the setup frame, opener highlighted")
    }

    @MainActor
    func testUndoToTheBottomReplaysTheOpeningMove() async throws {
        let store = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: move("e2e4"),
            openingReplayDelay: .milliseconds(1)
        )
        try await Task.sleep(for: .milliseconds(80))  // opener in

        store.undo()
        XCTAssertTrue(store.game.moves.isEmpty, "rewound to the raw seed")
        XCTAssertNil(store.lastMove)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.lastMove, move("e2e4"), "the opener replays itself")
        XCTAssertFalse(store.isUndoAnimation)
    }

    @MainActor
    func testResetReplaysTheOpeningMove() async throws {
        let store = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: move("e2e4"),
            openingReplayDelay: .milliseconds(1)
        )

        store.reset()
        XCTAssertTrue(store.game.moves.isEmpty)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.lastMove, move("e2e4"))
    }

    @MainActor
    func testAUserMoveDuringTheReplayWindowCancelsTheReplay() async throws {
        let store = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: move("e2e4"),
            openingReplayDelay: .milliseconds(80)
        )

        store.select(square("d2"))  // the machine's side, still on the raw frame
        store.select(square("d4"))
        XCTAssertEqual(store.lastMove, move("d2d4"))

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(store.lastMove, move("d2d4"), "the user's move wins; the opening replay stands down")
    }

    @MainActor
    func testBoardOpensOrientedLikeTheTrainingBoard() {
        XCTAssertFalse(AnalysisGameStore(seedFEN: Analysis.Position.startFEN).isFlipped)
        XCTAssertTrue(AnalysisGameStore(seedFEN: Analysis.Position.startFEN, startsFlipped: true).isFlipped)
    }

    @MainActor
    func testHeldColorFollowsTheSeedsSideToMove() {
        let whiteOpens = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            openingMove: move("e2e4"),
            openingReplayDelay: .seconds(60)
        )
        XCTAssertEqual(whiteOpens.heldColor, .black, "the machine opens white, so the solver holds black")

        let blackOpens = AnalysisGameStore(
            seedFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1",
            openingMove: move("e7e5"),
            openingReplayDelay: .seconds(60)
        )
        XCTAssertEqual(blackOpens.heldColor, .white)

        let freeBoard = AnalysisGameStore(
            seedFEN: Analysis.Position.startFEN,
            openingReplayDelay: .seconds(60)
        )
        XCTAssertNil(freeBoard.heldColor, "a free board without an opener holds no side")
    }

    // MARK: - SAN, move list, material

    func testMoveListLeadsWithTheOpeningMove() throws {
        var game = try Analysis.Game(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        game.play(move("e2e4"))
        XCTAssertEqual(game.moveList.map(\.san), ["e4"])
        XCTAssertEqual(game.moveList.first?.piece.assetName, "wP")
    }

    func testSANOfAStandardOpening() {
        var game = Analysis.Game.start()
        for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] {
            game.play(move(uci))
        }
        XCTAssertEqual(game.moveList.map(\.san), ["f3", "e5", "g4", "Qh4#"], "fool's mate carries the mate suffix")
        XCTAssertEqual(game.moveList.last?.piece.assetName, "bQ")
    }

    func testMoveNumbersFollowTheFullmoveClock() throws {
        var game = Analysis.Game.start()
        for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] {
            game.play(move(uci))
        }
        XCTAssertEqual(game.moveList.map(\.number), [1, 1, 2, 2], "white and black share the fullmove number")

        var midGame = try Analysis.Game(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 3 42"
        )
        midGame.play(move("e2e4"))
        midGame.play(move("e7e5"))
        XCTAssertEqual(midGame.moveList.map(\.number), [42, 42], "numbering continues the seed FEN's clock")
    }

    func testSANDisambiguatesByFileThenRank() throws {
        var byFile = try Analysis.Game(fen: "4k3/8/8/8/8/8/4K3/R6R w - - 0 1")
        byFile.play(move("a1d1"))
        XCTAssertEqual(byFile.moveList.last?.san, "Rad1", "rooks share the rank, so the file letter disambiguates")

        var byRank = try Analysis.Game(fen: "4k3/8/8/8/7R/8/8/K6R w - - 0 1")
        byRank.play(move("h1h3"))
        XCTAssertEqual(byRank.moveList.last?.san, "R1h3", "rooks share the file, so the rank digit disambiguates")
    }

    func testSANOfCapturesEnPassantAndCastling() throws {
        var capture = try Analysis.Game(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")
        capture.play(move("e5d5"))
        XCTAssertEqual(capture.moveList.last?.san, "exd5")

        var enPassant = try Analysis.Game(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        enPassant.play(move("e5d6"))
        XCTAssertEqual(enPassant.moveList.last?.san, "exd6")

        var castle = try Analysis.Game(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        castle.play(move("e1g1"))
        XCTAssertEqual(castle.moveList.last?.san, "O-O")

        var castleLong = try Analysis.Game(fen: "r3k3/8/8/8/8/8/8/4K3 b q - 0 1")
        castleLong.play(move("e8c8"))
        XCTAssertEqual(castleLong.moveList.last?.san, "O-O-O")
    }

    func testSANOfPromotionCarriesTheChosenPiece() throws {
        var game = try Analysis.Game(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1")
        game.play(Analysis.Move(from: square("a7"), to: square("a8"), promotion: .queen))
        XCTAssertEqual(game.moveList.last?.san, "a8=Q")
        XCTAssertEqual(game.moveList.last?.piece.kind, .queen, "the chip icon shows the promoted piece")
    }

    func testMaterialBalanceCountsBothSides() throws {
        let start = try Analysis.Position(fen: Analysis.Position.startFEN)
        XCTAssertEqual(start.materialBalance, 0)
        let whiteRookUp = try Analysis.Position(fen: "4k3/8/8/8/8/8/8/4K2R w - - 0 1")
        XCTAssertEqual(whiteRookUp.materialBalance, 5)
        let blackQueenUp = try Analysis.Position(fen: "4k2q/8/8/8/8/8/8/4K3 b - - 0 1")
        XCTAssertEqual(blackQueenUp.materialBalance, -9)
    }

    @MainActor
    func testUndoAndResetThroughTheStore() {
        let store = AnalysisGameStore(seedFEN: Analysis.Position.startFEN)
        XCTAssertFalse(store.canUndo)

        store.select(square("e2"))
        store.select(square("e4"))
        XCTAssertTrue(store.canUndo)

        store.undo()
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.position.fen, Analysis.Position.startFEN)

        store.select(square("d2"))
        store.select(square("d4"))
        store.reset()
        XCTAssertEqual(store.position.fen, Analysis.Position.startFEN)
        XCTAssertFalse(store.hasMoves)
    }
}
