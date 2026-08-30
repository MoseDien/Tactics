import XCTest
import SwiftData
@testable import DailyTactics

final class ChessAndPuzzleTests: XCTestCase {
    func testFENParsesPiecesAndSideToMove() throws {
        let board = try Board(fen: Puzzle.samples[0].fen)

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

        try session.resumeAfterIncorrectMove()
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
    func testProgressStoreMarksCompletion() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PuzzleProgress.self, configurations: config)
        let store = PuzzleProgressStore(context: ModelContext(container))

        XCTAssertFalse(store.isCompleted("p1"))
        XCTAssertEqual(store.completedCount(), 0)

        store.markCompleted("p1")
        XCTAssertTrue(store.isCompleted("p1"))
        XCTAssertEqual(store.completedCount(), 1)

        // Idempotent: re-marking the same puzzle does not double-count.
        store.markCompleted("p1")
        XCTAssertEqual(store.completedCount(), 1)

        store.markCompleted("p2")
        XCTAssertEqual(store.completedCount(), 2)
    }

    @MainActor
    func testProgressStoreRecordsFailures() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PuzzleProgress.self, configurations: config)
        let store = PuzzleProgressStore(context: ModelContext(container))

        XCTAssertEqual(store.failedCount(), 0)

        store.markFailed("p1")
        XCTAssertEqual(store.failedCount(), 1)

        // Idempotent: repeated wrong moves on the same puzzle don't double-count.
        store.markFailed("p1")
        XCTAssertEqual(store.failedCount(), 1)

        // Failure and completion are independent counts.
        store.markFailed("p2")
        store.markCompleted("p2")
        XCTAssertEqual(store.failedCount(), 2)
        XCTAssertEqual(store.completedCount(), 1)
    }

    @MainActor
    func testBoardAutoOrientsToPlayerColor() {
        let vm = TacticsViewModel(dataset: Puzzle.samples)
        // Whatever puzzle loaded first, the board faces the player's color.
        XCTAssertEqual(vm.isBoardFlipped, vm.playerColor == .black)

        // Re-orienting on each reload keeps the invariant.
        vm.restartBatch()
        XCTAssertEqual(vm.isBoardFlipped, vm.playerColor == .black)
    }

    func testPuzzleRatingRewardsHarderCleanSolvesMore() {
        let calculator = PuzzleRatingCalculator()

        XCTAssertGreaterThan(calculator.change(userRating: 1500, puzzleRating: 2200, solved: true),
                             calculator.change(userRating: 1500, puzzleRating: 1000, solved: true))
        XCTAssertLessThan(calculator.change(userRating: 1500, puzzleRating: 2200, solved: false), 0)
        XCTAssertGreaterThan(calculator.expectedScore(userRating: 1500, puzzleRating: 1000), 0.5)
    }

    @MainActor
    func testDifficultyModeFilteringUsesRatingBounds() {
        let context = ModelContext(try! ModelContainer(for: PuzzleRecord.self, PuzzleProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let store = PuzzleProgressStore(context: context)
        let puzzles = [
            Puzzle(id: "easy", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1200, themes: []),
            Puzzle(id: "mid", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1500, themes: []),
            Puzzle(id: "hard", fen: Puzzle.samples[0].fen, moves: Puzzle.samples[0].moves, rating: 1900, themes: [])
        ]
        puzzles.forEach { context.insert(PuzzleRecord(puzzle: $0)) }
        try? context.save()
        let easy = store.fetchUnattemptedRound(count: 1, difficulty: .easy, userRating: 1500)
        let hard = store.fetchUnattemptedRound(count: 1, difficulty: .hard, userRating: 1500)
        XCTAssertTrue(easy.allSatisfy { ($0.rating ?? 0) <= 1700 })
        XCTAssertTrue(hard.allSatisfy { ($0.rating ?? 0) >= 1300 })
    }

    @MainActor
    func testHintImmediatelyCostsRating() async throws {
        let defaults = UserDefaults(suiteName: "hint-penalty-\(UUID().uuidString)")!
        let store = UserRatingStore(defaults: defaults)
        let vm = TacticsViewModel(dataset: Puzzle.samples, ratingStore: store)

        // Wait for the opening machine move so a hint is enabled.
        vm.start()
        var waited = 0
        while vm.state != .waitingForMove && waited < 40 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        XCTAssertEqual(vm.state, .waitingForMove)

        let before = vm.userRating
        vm.requestHint()

        // Using a hint is a failure: rating drops right away and the round
        // marker records it as wrong.
        XCTAssertLessThan(vm.userRating, before, "Hint should cost rating points")
        XCTAssertLessThan(vm.lastRatingDelta ?? 0, 0, "Hint should record a negative delta")

        // A second tap must not stack another penalty.
        let afterFirstHint = vm.userRating
        vm.requestHint()
        XCTAssertEqual(vm.userRating, afterFirstHint)
    }

    // MARK: - DB-backed round selection

    @MainActor
    func testFetchUnattemptedRoundExcludesAttemptedAndFallsBack() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PuzzleRecord.self, PuzzleProgress.self, configurations: config)
        let context = ModelContext(container)
        let store = PuzzleProgressStore(context: context)

        let puzzles = (0..<7).map { i in
            Puzzle(id: "p\(i)", fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1", moves: ["e1e2"], rating: 1500, themes: [])
        }
        puzzles.forEach { context.insert(PuzzleRecord(puzzle: $0)) }
        try context.save()

        // Mark two as attempted.
        store.markAttempted("p0")
        store.markAttempted("p1")

        // Enough unattempted remain (5) → returns exactly 5, none attempted.
        let round = store.fetchUnattemptedRound(count: 5)
        XCTAssertEqual(round.count, 5)
        let roundIDs = Set(round.map(\.id))
        XCTAssertFalse(roundIDs.contains("p0"))
        XCTAssertFalse(roundIDs.contains("p1"))

        // Mark 6 of 7 attempted → fewer than 5 unattempted → falls back to
        // random-over-all so a round is still returned.
        for i in 2...6 { store.markAttempted("p\(i)") }
        let fallback = store.fetchUnattemptedRound(count: 5)
        XCTAssertEqual(fallback.count, 5)
    }

    @MainActor
    func testImportAllBundledIsIdempotent() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PuzzleRecord.self, configurations: config)
        let context = ModelContext(container)
        let importer = PuzzleLibraryImporter(context: context)

        await importer.importAllBundled { _ in }
        let firstCount = try context.fetchCount(FetchDescriptor<PuzzleRecord>())
        try XCTSkipUnless(firstCount > 0, "Bundled tier JSONs are not present in the test host")

        // Re-running must not duplicate rows (dedup by puzzleId).
        await importer.importAllBundled { _ in }
        let secondCount = try context.fetchCount(FetchDescriptor<PuzzleRecord>())
        XCTAssertEqual(secondCount, firstCount)
    }
}
