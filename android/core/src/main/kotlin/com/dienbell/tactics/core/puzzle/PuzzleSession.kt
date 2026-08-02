package com.dienbell.tactics.core.puzzle

import com.dienbell.tactics.core.chess.Board
import com.dienbell.tactics.core.chess.ChessMove
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.core.chess.PieceKind
import com.dienbell.tactics.core.chess.Square

enum class PuzzleSessionState { WAITING_FOR_MOVE, OPPONENT_MOVING, INCORRECT_MOVE, SOLVED }

/**
 * Drives a single puzzle's tactical line. Lichess lines begin with the opponent's
 * setup move (`moves[0]`); the user starts at `moves[1]` and turns alternate.
 *
 * Ported from the Swift `PuzzleSession` struct. Swift uses a value type with
 * `mutating` functions; Kotlin uses a class that mutates in place.
 */
class PuzzleSession(val puzzle: Puzzle) {

    sealed class Error(message: String) : Exception(message) {
        class EmptyLine : Error("puzzle line is empty")
        class InvalidMove(uci: String) : Error("invalid move: $uci")
        class MoveHasNoPiece(uci: String) : Error("move has no piece: $uci")
    }

    var board: Board
        private set
    var state: PuzzleSessionState
        private set
    var currentMoveIndex: Int
        private set
    var lastMove: ChessMove? = null
        private set

    /** True while the displayed position was reached by review stepping rather
     *  than the live solve flow. The auto-reply ignores review positions. */
    var isReviewing: Boolean = false
        private set

    init {
        if (puzzle.moves.isEmpty()) throw Error.EmptyLine()
        puzzle.moves.forEach { uci ->
            if (ChessMove.from(uci) == null) throw Error.InvalidMove(uci)
        }
        board = Board.parse(puzzle.fen)
        state = PuzzleSessionState.OPPONENT_MOVING
        currentMoveIndex = 0
    }

    val expectedMove: ChessMove?
        get() = puzzle.moves.getOrNull(currentMoveIndex)?.let(ChessMove::from)

    /** Lichess puzzle lines begin with the setup move made by the opponent. */
    val userColor: PieceColor
        get() = board.sideToMove.opponent

    /** Whether `move` is a legal chess move for the side the user controls. */
    fun isLegalUserMove(move: ChessMove): Boolean = board.isLegal(move, userColor)

    /** Whether `move` sends a pawn to its promotion rank (UI auto-promotes to queen). */
    fun moveNeedsPromotion(move: ChessMove): Boolean {
        val piece = board.pieces[move.from] ?: return false
        return piece.kind == PieceKind.PAWN && (move.to.rank == 0 || move.to.rank == 7)
    }

    fun submitUserMove(move: ChessMove) {
        if (state != PuzzleSessionState.WAITING_FOR_MOVE && state != PuzzleSessionState.INCORRECT_MOVE) return
        isReviewing = false

        if (move != expectedMove) {
            // Wrong move: the view layer records it as a failure; the user may retry.
            state = PuzzleSessionState.INCORRECT_MOVE
            return
        }

        if (!board.apply(move)) throw Error.MoveHasNoPiece(move.uci)
        lastMove = move
        currentMoveIndex += 1
        state = if (currentMoveIndex == puzzle.moves.size) {
            PuzzleSessionState.SOLVED
        } else {
            PuzzleSessionState.OPPONENT_MOVING
        }
    }

    fun applyOpponentMove() {
        // The live solve flow keeps isReviewing false, so the auto-reply only
        // fires for the expected opponent reply — never during manual review.
        if (state != PuzzleSessionState.OPPONENT_MOVING || isReviewing) return
        val move = expectedMove ?: return
        if (!board.apply(move)) throw Error.MoveHasNoPiece(move.uci)
        lastMove = move
        currentMoveIndex += 1
        state = if (currentMoveIndex == puzzle.moves.size) {
            PuzzleSessionState.SOLVED
        } else {
            PuzzleSessionState.WAITING_FOR_MOVE
        }
    }

    fun resumeAfterIncorrectMove() {
        if (state == PuzzleSessionState.INCORRECT_MOVE) {
            state = PuzzleSessionState.WAITING_FOR_MOVE
        }
    }

    // region Review stepping

    /** 1-based number of the user move awaiting a guess, clamped to the total. */
    val currentMoveNumber: Int
        get() = minOf((currentMoveIndex + 1) / 2, totalUserMoves)

    /** How many user moves complete the tactical line. */
    val totalUserMoves: Int
        get() = puzzle.moves.size / 2

    val canStepForward: Boolean
        get() = currentMoveIndex < puzzle.moves.size

    val canStepBack: Boolean
        get() = currentMoveIndex > 1

    fun stepForward() {
        if (currentMoveIndex < puzzle.moves.size) replay(currentMoveIndex + 1)
    }

    fun stepBack() {
        if (currentMoveIndex > 1) replay(currentMoveIndex - 1)
    }

    /** Recompute the board, last move and state by replaying the first `target`
     *  moves of the line from the initial FEN. Powers the manual stepping controls. */
    private fun replay(target: Int) {
        val clamped = target.coerceIn(1, puzzle.moves.size)
        val rebuilt = Board.parse(puzzle.fen)
        for (uci in puzzle.moves.subList(0, clamped)) {
            val move = ChessMove.from(uci) ?: throw Error.InvalidMove(uci)
            if (!rebuilt.apply(move)) throw Error.MoveHasNoPiece(uci)
        }
        board = rebuilt
        currentMoveIndex = clamped
        lastMove = ChessMove.from(puzzle.moves[clamped - 1])
        isReviewing = true
        state = when {
            clamped == puzzle.moves.size -> PuzzleSessionState.SOLVED
            clamped % 2 == 0 -> PuzzleSessionState.OPPONENT_MOVING
            else -> PuzzleSessionState.WAITING_FOR_MOVE
        }
    }

    fun restart() {
        board = Board.parse(puzzle.fen)
        state = PuzzleSessionState.OPPONENT_MOVING
        currentMoveIndex = 0
        lastMove = null
        isReviewing = false
    }

    // endregion
}
