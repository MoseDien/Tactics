package com.dienbell.tactics.core

import com.dienbell.tactics.core.chess.Board
import com.dienbell.tactics.core.chess.ChessMove
import com.dienbell.tactics.core.chess.Piece
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.core.chess.PieceColor.BLACK
import com.dienbell.tactics.core.chess.PieceColor.WHITE
import com.dienbell.tactics.core.chess.PieceKind.KING
import com.dienbell.tactics.core.chess.PieceKind.KNIGHT
import com.dienbell.tactics.core.chess.PieceKind.ROOK
import com.dienbell.tactics.core.chess.Square
import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.core.puzzle.PuzzleSession
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.INCORRECT_MOVE
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.OPPONENT_MOVING
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.SOLVED
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.WAITING_FOR_MOVE
import com.dienbell.tactics.core.rating.PuzzleRatingCalculator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ChessAndPuzzleTest {

    @Test fun fenParsesPiecesAndSideToMove() {
        val board = Board.parse(Puzzle.SAMPLES[0].fen)

        assertEquals(WHITE, board.sideToMove)
        assertEquals(Piece(WHITE, KING), board.pieces[Square.from("e1")])
        assertEquals(Piece(BLACK, KNIGHT), board.pieces[Square.from("d5")])
        assertEquals(Piece(BLACK, ROOK), board.pieces[Square.from("a8")])
    }

    @Test fun squareAndUciRoundTrip() {
        assertEquals("e8", Square.from("e8")?.notation)
        assertEquals("h5e8", ChessMove.from("h5e8")?.uci)
        assertEquals(com.dienbell.tactics.core.chess.PieceKind.QUEEN, ChessMove.from("a7a8q")?.promotion)
        assertNull(ChessMove.from("not-a-move"))
    }

    @Test fun expectedFirstMoveIsRecognized() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])

        assertEquals(OPPONENT_MOVING, session.state)
        assertEquals(Puzzle.SAMPLES[0].moves[0], session.expectedMove?.uci)
        assertEquals(BLACK, session.userColor)

        session.applyOpponentMove()

        assertEquals(WAITING_FOR_MOVE, session.state)
        assertEquals(Puzzle.SAMPLES[0].moves[1], session.expectedMove?.uci)
    }

    @Test fun wrongMoveIsRejectedButRetriableAndLeavesBoardUnchanged() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])
        session.applyOpponentMove()
        val originalBoard = session.board
        val expectedMove = session.expectedMove!!
        val wrongTarget = Square.from(if (expectedMove.to.notation == "e7") "e6" else "e7")!!

        session.submitUserMove(ChessMove(expectedMove.from, wrongTarget))

        // Wrong move is rejected but the user may retry; the board is untouched.
        assertEquals(INCORRECT_MOVE, session.state)
        assertSame(originalBoard, session.board)

        session.resumeAfterIncorrectMove()
        assertEquals(WAITING_FOR_MOVE, session.state)
    }

    @Test fun completeLineReachesSolvedAndRestartRestoresPuzzle() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])
        val firstUserMove = ChessMove.from(Puzzle.SAMPLES[0].moves[1])!!
        val finalUserMove = ChessMove.from(Puzzle.SAMPLES[0].moves[3])!!

        session.applyOpponentMove()
        assertEquals(Puzzle.SAMPLES[0].moves[0], session.lastMove!!.uci)

        session.submitUserMove(firstUserMove)
        assertEquals(OPPONENT_MOVING, session.state)

        session.applyOpponentMove()
        assertEquals(WAITING_FOR_MOVE, session.state)
        assertEquals(Puzzle.SAMPLES[0].moves[2], session.lastMove!!.uci)

        session.submitUserMove(finalUserMove)
        assertEquals(SOLVED, session.state)
        assertEquals(Puzzle.SAMPLES[0].moves[3], session.lastMove!!.uci)

        session.restart()
        assertEquals(OPPONENT_MOVING, session.state)
        assertEquals(0, session.currentMoveIndex)
        assertEquals(WHITE, session.board.sideToMove)
        assertNull(session.lastMove)
    }

    @Test fun fourPlyLichessLineAlternatesMachineAndPlayer() {
        val puzzle = Puzzle(
            id = "machine-first",
            fen = "6k1/8/8/3N4/8/8/8/4r1K1 b - - 0 1",
            moves = listOf("e1d1", "d5c3", "d1c2", "c3e2"),
            rating = null,
            themes = listOf("fork"),
        )
        val session = PuzzleSession(puzzle)

        assertEquals(OPPONENT_MOVING, session.state)
        session.applyOpponentMove()
        assertEquals(WAITING_FOR_MOVE, session.state)
        assertEquals("d5c3", session.expectedMove?.uci)

        session.submitUserMove(ChessMove.from("d5c3")!!)
        assertEquals(OPPONENT_MOVING, session.state)
        session.applyOpponentMove()
        assertEquals(WAITING_FOR_MOVE, session.state)
        assertEquals("c3e2", session.expectedMove?.uci)

        session.submitUserMove(ChessMove.from("c3e2")!!)
        assertEquals(SOLVED, session.state)
    }

    // region Review stepping

    @Test fun stepForwardAdvancesOnePlyAtATime() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])

        session.stepForward()
        assertEquals(1, session.currentMoveIndex)
        assertEquals(WAITING_FOR_MOVE, session.state)
        assertTrue(session.isReviewing)
        assertTrue(session.canStepForward)
        assertFalse(session.canStepBack)

        session.stepForward()
        assertEquals(2, session.currentMoveIndex)
        assertEquals(OPPONENT_MOVING, session.state)
    }

    @Test fun steppingTheFullLineReachesSolved() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])
        val total = Puzzle.SAMPLES[0].moves.size

        for (expected in 1..total) {
            session.stepForward()
            assertEquals(expected, session.currentMoveIndex)
        }

        assertEquals(SOLVED, session.state)
        assertFalse(session.canStepForward)
    }

    @Test fun stepBackRewindsPosition() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])
        session.stepForward() // index 1: knight still on d5
        session.stepForward() // index 2: Nc3 played, knight on c3

        val c3 = Square.from("c3")!!
        assertNotNull(session.board.pieces[c3])

        session.stepBack() // back to index 1
        assertEquals(1, session.currentMoveIndex)
        assertNull(session.board.pieces[c3])
        assertEquals(Piece(BLACK, KNIGHT), session.board.pieces[Square.from("d5")])
    }

    @Test fun liveGuessClearsReviewingFlag() {
        val session = PuzzleSession(Puzzle.SAMPLES[0])
        session.stepForward()
        assertTrue(session.isReviewing)

        session.submitUserMove(ChessMove.from(Puzzle.SAMPLES[0].moves[1])!!)
        assertFalse(session.isReviewing)
    }

    // endregion

    // region Bundled samples

    @Test fun allSamplesArePlayableToSolvedWithUniqueIds() {
        val seenIds = mutableSetOf<String>()
        for (puzzle in Puzzle.SAMPLES) {
            assertFalse("Duplicate puzzle id: ${puzzle.id}", seenIds.contains(puzzle.id))
            seenIds.add(puzzle.id)

            val session = PuzzleSession(puzzle)
            while (session.canStepForward) session.stepForward()
            assertEquals("Puzzle ${puzzle.id} did not reach solved", SOLVED, session.state)
        }
    }

    // endregion

    // region Legal move validation

    @Test fun legalMovesRespectPieceShapesAndBlocking() {
        val rookBoard = Board.parse("7k/8/8/8/8/8/8/R3K3 w - - 0 1")
        assertTrue(rookBoard.isLegal(ChessMove.from("a1a7")!!, WHITE))    // rook straight, clear
        assertFalse(rookBoard.isLegal(ChessMove.from("a1b2")!!, WHITE))   // diagonal — not a rook move
        assertTrue(rookBoard.isLegal(ChessMove.from("e1d1")!!, WHITE))    // king one square
        assertFalse(rookBoard.isLegal(ChessMove.from("e1c1")!!, WHITE))   // king two squares

        val bishopBoard = Board.parse("7k/8/8/8/8/4P3/8/2B1K3 w - - 0 1")
        assertTrue(bishopBoard.isLegal(ChessMove.from("c1d2")!!, WHITE))  // one step diagonal
        assertFalse(bishopBoard.isLegal(ChessMove.from("c1g5")!!, WHITE)) // blocked by the e3 pawn

        val knightBoard = Board.parse("7k/8/8/8/8/2P5/8/1N2K3 w - - 0 1")
        assertTrue(knightBoard.isLegal(ChessMove.from("b1a3")!!, WHITE))  // L-move to empty
        assertFalse(knightBoard.isLegal(ChessMove.from("b1c3")!!, WHITE)) // L-move onto own pawn

        val emptyBoard = Board.parse("7k/8/8/8/8/8/8/4K3 w - - 0 1")
        assertFalse(emptyBoard.isLegal(ChessMove.from("a1a2")!!, WHITE))  // no piece on origin
    }

    @Test fun pawnPushAndCapture() {
        val board = Board.parse("7k/8/8/8/8/3p4/4P3/4K3 w - - 0 1")
        assertTrue(board.isLegal(ChessMove.from("e2e4")!!, WHITE))   // two-square start push
        assertTrue(board.isLegal(ChessMove.from("e2e3")!!, WHITE))   // one-square push
        assertTrue(board.isLegal(ChessMove.from("e2d3")!!, WHITE))   // diagonal capture
        assertFalse(board.isLegal(ChessMove.from("e2f3")!!, WHITE))  // diagonal to empty — no capture
    }

    // endregion

    // region Special moves (castling / en passant) in apply

    @Test fun castlingAlsoRelocatesTheRook() {
        val board = Board.parse("4k3/8/8/8/8/8/8/4K2R w - - 0 1")
        assertTrue(board.apply(ChessMove.from("e1g1")!!))
        assertNotNull(board.pieces[Square.from("g1")!!]) // king on g1
        assertNotNull(board.pieces[Square.from("f1")!!]) // rook on f1
        assertNull(board.pieces[Square.from("e1")!!])
        assertNull(board.pieces[Square.from("h1")!!])
    }

    @Test fun enPassantRemovesTheCapturedPawn() {
        val board = Board.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        assertTrue(board.apply(ChessMove.from("e5d6")!!))
        assertNotNull(board.pieces[Square.from("d6")!!]) // white pawn lands on d6
        assertNull(board.pieces[Square.from("d5")!!])    // captured black pawn gone
        assertNull(board.pieces[Square.from("e5")!!])    // origin vacated
    }

    // endregion

    // region Rating

    @Test fun puzzleRatingRewardsHarderCleanSolvesMore() {
        val calculator = PuzzleRatingCalculator()

        assertTrue(
            calculator.change(userRating = 1500, puzzleRating = 2200, solved = true) >
                calculator.change(userRating = 1500, puzzleRating = 1000, solved = true),
        )
        assertTrue(calculator.change(userRating = 1500, puzzleRating = 2200, solved = false) < 0)
        assertTrue(calculator.expectedScore(userRating = 1500, puzzleRating = 1000) > 0.5)
    }

    @Test fun ratingLevelClampsAndBandsByHundred() {
        val start = com.dienbell.tactics.core.rating.RatingLevel(1500)
        assertEquals(1500, start.lowerBound)
        assertEquals(1500 until 1600, start.ratingRange)
        assertEquals(1000, com.dienbell.tactics.core.rating.RatingLevel(850).lowerBound) // clamps up
        assertEquals(1900, com.dienbell.tactics.core.rating.RatingLevel(2400).lowerBound) // clamps down
        assertEquals(1500, com.dienbell.tactics.core.rating.RatingLevel(1599).lowerBound) // floors to band
    }
}
