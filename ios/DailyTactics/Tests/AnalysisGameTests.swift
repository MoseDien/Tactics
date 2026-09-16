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
