package com.dienbell.tactics.ui.rating

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dienbell.tactics.core.chess.ChessMove
import com.dienbell.tactics.core.chess.Piece
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.core.chess.PieceKind
import com.dienbell.tactics.core.chess.Square
import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.core.puzzle.PuzzleSession
import com.dienbell.tactics.core.puzzle.PuzzleSessionState
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.INCORRECT_MOVE
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.OPPONENT_MOVING
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.SOLVED
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.WAITING_FOR_MOVE
import com.dienbell.tactics.data.RatingAssessmentPlan
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AssessmentUiState(
    val index: Int = 0,
    val count: Int = 0,
    val displayedPosition: Map<Square, Piece> = emptyMap(),
    val selectedSquare: Square? = null,
    val hintMove: ChessMove? = null,
    val lastMove: ChessMove? = null,
    val isFlipped: Boolean = false,
    val playerColor: PieceColor = PieceColor.WHITE,
    val results: List<Boolean?> = emptyList(),
    val solvedCount: Int = 0,
    val finished: Boolean = false,
    val baselineRating: Int = 1500,
    val importing: Boolean = false,
    val importProgress: Float = 0f,
)

/**
 * Baseline rating assessment: each puzzle gets one attempt, then advances.
 * On completion, derives a baseline rating and imports the matching tier.
 */
class RatingAssessmentViewModel(
    pool: List<Puzzle>,
    private val count: Int = 4,
    private val onContinue: (suspend (baseline: Int, onProgress: (Float) -> Unit) -> Unit),
) : ViewModel() {

    private val puzzles: List<Puzzle> = RatingAssessmentPlan.select(pool, count)
    private var index = 0
    private var session = PuzzleSession(puzzles.first())
    private var selectedSquare: Square? = null
    private var isFlipped = false
    private var results: MutableList<Boolean?> = MutableList(puzzles.size) { null }
    private var solvedCount = 0

    private val _ui = MutableStateFlow(initialState())
    val ui: StateFlow<AssessmentUiState> = _ui.asStateFlow()

    init { orient(); emit() }

    fun start() {
        if (session.state == OPPONENT_MOVING && session.currentMoveIndex == 0) {
            viewModelScope.launch { playOpponent() }
        }
    }

    fun select(square: Square) {
        if (session.state != WAITING_FOR_MOVE && session.state != INCORRECT_MOVE) return
        if (session.state == INCORRECT_MOVE) return // assessment: no retry after a wrong move
        selectedSquare = when {
            selectedSquare == null && session.board.pieces[square]?.color == session.userColor -> square
            selectedSquare == square -> null
            session.board.pieces[square]?.color == session.userColor -> square
            selectedSquare != null -> { attemptMove(selectedSquare!!, square); null }
            else -> selectedSquare
        }
        emit()
    }

    fun continueAssessment() {
        val baseline = _ui.value.baselineRating
        viewModelScope.launch {
            _ui.update { it.copy(importing = true) }
            onContinue(baseline) { p -> _ui.update { it.copy(importProgress = p) } }
            _ui.update { it.copy(importing = false) }
        }
    }

    // region internals

    private fun attemptMove(from: Square, to: Square) {
        var move = ChessMove(from, to)
        if (session.moveNeedsPromotion(move)) move = ChessMove(from, to, PieceKind.QUEEN)
        val isExpected = move == session.expectedMove
        if (!isExpected && !session.isLegalUserMove(move)) return
        session.submitUserMove(move)
        when (session.state) {
            SOLVED -> {
                results[index] = true
                solvedCount += 1
                emit()
                advanceAfter(650)
            }
            OPPONENT_MOVING -> viewModelScope.launch { playOpponent() }
            INCORRECT_MOVE -> {
                results[index] = false
                emit()
                advanceAfter(650)
            }
            else -> Unit
        }
    }

    private suspend fun playOpponent() {
        delay(450)
        session.applyOpponentMove()
        if (session.state == SOLVED) {
            results[index] = true
            solvedCount += 1
            emit()
            advanceAfter(650)
        } else {
            emit()
        }
    }

    private fun advanceAfter(ms: Long) {
        viewModelScope.launch {
            delay(ms)
            if (index < puzzles.size - 1) {
                index += 1
                session = PuzzleSession(puzzles[index])
                selectedSquare = null
                orient()
                emit()
                viewModelScope.launch { playOpponent() }
            } else {
                finish()
            }
        }
    }

    private fun finish() {
        val baseline = RatingAssessmentPlan.baselineRating(puzzles, solvedCount)
        _ui.update { it.copy(finished = true, baselineRating = baseline) }
    }

    private fun orient() { isFlipped = session.userColor == PieceColor.BLACK }

    private fun initialState() = AssessmentUiState(
        index = 0,
        count = puzzles.size,
        results = results.toList(),
        displayedPosition = session.board.pieces,
        playerColor = session.userColor,
        isFlipped = session.userColor == PieceColor.BLACK,
    )

    private fun emit() {
        _ui.update {
            it.copy(
                index = index,
                count = puzzles.size,
                displayedPosition = session.board.pieces,
                selectedSquare = selectedSquare,
                lastMove = session.lastMove,
                playerColor = session.userColor,
                isFlipped = isFlipped,
                results = results.toList(),
                solvedCount = solvedCount,
            )
        }
    }
}
