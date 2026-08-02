package com.dienbell.tactics.ui.tactics

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dienbell.tactics.core.chess.ChessMove
import com.dienbell.tactics.core.chess.Piece
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.core.chess.Square
import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.core.puzzle.PuzzleSession
import com.dienbell.tactics.core.puzzle.PuzzleSessionState
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.INCORRECT_MOVE
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.OPPONENT_MOVING
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.SOLVED
import com.dienbell.tactics.core.puzzle.PuzzleSessionState.WAITING_FOR_MOVE
import com.dienbell.tactics.core.rating.PuzzleRatingCalculator
import com.dienbell.tactics.core.rating.RatingLevel
import com.dienbell.tactics.data.PuzzleProgressStore
import com.dienbell.tactics.data.UserRatingStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed class TacticsFeedback {
    data class Instruction(val message: String) : TacticsFeedback()
    data class Error(val message: String) : TacticsFeedback()
    data object OpponentMoving : TacticsFeedback()
    data object OpponentReply : TacticsFeedback()
    data object IncorrectMove : TacticsFeedback()
    data object Reviewing : TacticsFeedback()
    data object PuzzleComplete : TacticsFeedback()
    data object TrainingComplete : TacticsFeedback()
}

data class TacticsUiState(
    val puzzleNumber: Int = 1,
    val puzzleCount: Int = 0,
    val displayedPosition: Map<Square, Piece> = emptyMap(),
    val lastMove: ChessMove? = null,
    val selectedSquare: Square? = null,
    val hintMove: ChessMove? = null,
    val playerColor: PieceColor = PieceColor.WHITE,
    val isBoardFlipped: Boolean = false,
    val sessionState: PuzzleSessionState = OPPONENT_MOVING,
    val inReview: Boolean = false,
    val isReviewing: Boolean = false,
    val canStepForward: Boolean = false,
    val canStepBack: Boolean = false,
    val hintEnabled: Boolean = false,
    val currentMoveNumber: Int = 0,
    val totalUserMoves: Int = 0,
    val userRating: Int = 1500,
    val lastRatingDelta: Int? = null,
    val results: List<PuzzleOutcome?> = emptyList(),
    val levelTransition: RatingLevel? = null,
    val feedback: TacticsFeedback = TacticsFeedback.Instruction("Find the winning move"),
) {
    val isBatchComplete: Boolean get() = puzzleNumber == puzzleCount && sessionState == SOLVED
}

/**
 * Coordinates a tactics round: session flow, hint (= immediate loss), rating,
 * review, level-transition reload, round results, and the next-puzzle delay.
 * Ported from the SwiftUI `TacticsViewModel`.
 */
class TacticsViewModel(
    private val dataset: List<Puzzle>,
    private val ratingStore: UserRatingStore,
    private val progressStore: PuzzleProgressStore? = null,
    private val calculator: PuzzleRatingCalculator = PuzzleRatingCalculator(),
    private val dailyPuzzleCount: Int = 5,
    private val importTier: (suspend (Int) -> Unit)? = null,
    private val scopedPuzzles: (suspend (Int) -> List<Puzzle>)? = null,
) : ViewModel() {

    private var source: List<Puzzle> = dataset.ifEmpty { Puzzle.SAMPLES }
    private var puzzles: List<Puzzle> = pickRandom(source, dailyPuzzleCount)
    private var currentIndex = 0
    private var session = PuzzleSession(puzzles.first())

    private var selectedSquare: Square? = null
    private var attemptedMove: ChessMove? = null
    private var hintMove: ChessMove? = null
    private var hadMistake = false
    private var ratingAppliedForPuzzle = false
    private var firstAttemptWasCorrect = false
    private var isAdvancing = false
    private var isBoardFlipped = false
    private var results: MutableList<PuzzleOutcome?> = MutableList(puzzles.size) { null }
    private val attemptedPuzzleIds = mutableSetOf<String>()

    private var userRating = ratingStore.rating()
    private var lastRatingDelta: Int? = null
    private var levelTransition: RatingLevel? = null

    private val _ui = MutableStateFlow(TacticsUiState())
    val ui: StateFlow<TacticsUiState> = _ui.asStateFlow()

    init {
        orientBoard()
        emit()
    }

    fun start() {
        if (session.state == OPPONENT_MOVING && session.currentMoveIndex == 0) {
            viewModelScope.launch { playOpponentMove() }
        }
    }

    fun toggleBoardFlip() { isBoardFlipped = !isBoardFlipped; emit() }

    fun acknowledgeLevelTransition() { levelTransition = null; emit() }

    /** Imports the new tier (if wired) and reloads the in-memory dataset from it. */
    fun confirmLevelTransition() {
        val rating = userRating
        viewModelScope.launch {
            importTier?.invoke(rating)
            scopedPuzzles?.invoke(rating)?.let { reload(it) }
            acknowledgeLevelTransition()
        }
    }

    fun select(square: Square) {
        if (inReview || (session.state != WAITING_FOR_MOVE && session.state != INCORRECT_MOVE)) return
        attemptedMove = null
        hintMove = null
        if (session.state == INCORRECT_MOVE) session.resumeAfterIncorrectMove()

        val selected = selectedSquare
        when {
            selected == null -> {
                if (session.board.pieces[square]?.color == session.userColor) selectedSquare = square
            }
            selected == square -> selectedSquare = null
            session.board.pieces[square]?.color == session.userColor -> selectedSquare = square
            else -> attemptMove(from = selected, to = square)
        }
        emit()
    }

    fun requestHint() {
        if (!hintEnabled) return
        val expected = session.expectedMove ?: return
        hadMistake = true
        hintMove = expected
        applyHintPenalty()
        emit()
    }

    fun stepForward() {
        if (!canStepForward) return
        runCatching { session.stepForward() }
            .onFailure { /* keep board; error is non-fatal for review */ }
        clearSelection()
        emit()
    }

    fun stepBack() {
        if (!canStepBack) return
        runCatching { session.stepBack() }.onFailure {}
        clearSelection()
        emit()
    }

    fun nextPuzzle() {
        if (isAdvancing || currentIndex >= puzzles.size - 1) return
        isAdvancing = true
        val target = currentIndex + 1
        // A brief beat so the transition reads as deliberate, not an instant snap.
        viewModelScope.launch {
            delay(NEXT_PUZZLE_DELAY_MS)
            currentIndex = target
            loadPuzzle(target)
            isAdvancing = false
            emit()
        }
    }

    fun restartBatch() { reshuffleBatch() }

    fun restart() { loadPuzzle(currentIndex); emit() }

    fun reload(dataset: List<Puzzle>) {
        if (dataset.isEmpty()) return
        source = dataset
        reshuffleBatch()
    }

    // region Internals

    private fun reshuffleBatch() {
        val available = source.filter { it.id !in attemptedPuzzleIds }
        val pool = if (available.size >= dailyPuzzleCount) available else source
        puzzles = pickRandom(pool, dailyPuzzleCount)
        results = MutableList(puzzles.size) { null }
        currentIndex = 0
        loadPuzzle(0)
        emit()
    }

    private fun loadPuzzle(index: Int) {
        session = PuzzleSession(puzzles[index])
        selectedSquare = null
        hintMove = null
        attemptedMove = null
        hadMistake = false
        firstAttemptWasCorrect = false
        ratingAppliedForPuzzle = false
        lastRatingDelta = null
        orientBoard()
        viewModelScope.launch { playOpponentMove() }
    }

    private fun attemptMove(from: Square, to: Square) {
        hintMove = null
        var move = ChessMove(from, to)
        if (session.moveNeedsPromotion(move)) move = ChessMove(from, to, com.dienbell.tactics.core.chess.PieceKind.QUEEN)

        val isExpected = move == session.expectedMove
        if (!isExpected && !session.isLegalUserMove(move)) return

        val puzzleId = puzzles[currentIndex].id
        val isFirstAttempt = puzzleId !in attemptedPuzzleIds
        if (isFirstAttempt) {
            firstAttemptWasCorrect = isExpected
            attemptedPuzzleIds.add(puzzleId)
            viewModelScope.launch { progressStore?.markAttempted(puzzleId) }
        }
        selectedSquare = null

        session.submitUserMove(move)

        when (session.state) {
            INCORRECT_MOVE -> {
                recordOutcome(PuzzleOutcome.WRONG, currentIndex)
                hadMistake = true
                attemptedMove = move
                viewModelScope.launch { progressStore?.markFailed(puzzleId) }
                viewModelScope.launch {
                    delay(WRONG_MOVE_PREVIEW_MS)
                    if (attemptedMove == move) attemptedMove = null
                    emit()
                }
            }
            SOLVED -> markCurrentSolved()
            OPPONENT_MOVING -> viewModelScope.launch { playOpponentMove() }
            else -> Unit
        }
    }

    private suspend fun playOpponentMove() {
        delay(OPPONENT_REPLY_MS)
        session.applyOpponentMove()
        if (session.state == SOLVED) markCurrentSolved()
        emit()
    }

    private fun markCurrentSolved() {
        if (ratingAppliedForPuzzle) return
        ratingAppliedForPuzzle = true
        viewModelScope.launch { progressStore?.markCompleted(puzzles[currentIndex].id) }
        recordOutcome(PuzzleOutcome.CORRECT, currentIndex)
        if (!firstAttemptWasCorrect) return
        val puzzleRating = puzzles[currentIndex].rating ?: userRating
        val cleanSolve = !hadMistake && hintMove == null
        applySolveRating(solved = cleanSolve, puzzleRating = puzzleRating)
    }

    /** A hint is a give-up: score an immediate loss, mark attempted. Idempotent. */
    private fun applyHintPenalty() {
        if (ratingAppliedForPuzzle) return
        ratingAppliedForPuzzle = true
        recordOutcome(PuzzleOutcome.WRONG, currentIndex)
        applySolveRating(solved = false, puzzleRating = puzzles[currentIndex].rating ?: userRating)
        val puzzleId = puzzles[currentIndex].id
        attemptedPuzzleIds.add(puzzleId)
        viewModelScope.launch { progressStore?.markAttempted(puzzleId) }
    }

    private fun applySolveRating(solved: Boolean, puzzleRating: Int) {
        val delta = calculator.change(userRating = userRating, puzzleRating = puzzleRating, solved = solved)
        userRating = ratingStore.apply(delta)
        lastRatingDelta = delta
        val newLevel = RatingLevel(userRating)
        if (newLevel != ratingStore.level()) {
            levelTransition = newLevel
            ratingStore.set(userRating)
        }
    }

    private fun recordOutcome(outcome: PuzzleOutcome, index: Int) {
        if (index in results.indices && results[index] == null) results[index] = outcome
    }

    private fun clearSelection() { selectedSquare = null; attemptedMove = null; hintMove = null }

    private fun orientBoard() { isBoardFlipped = session.userColor == PieceColor.BLACK }

    private fun displayedPosition(): Map<Square, Piece> {
        val base = session.board.pieces
        val attempt = attemptedMove ?: return base
        val piece = base[attempt.from] ?: return base
        return base.toMutableMap().apply { remove(attempt.from); put(attempt.to, piece) }
    }

    private val inReview: Boolean get() = session.state == SOLVED || session.isReviewing
    private val canStepForward: Boolean get() = inReview && session.canStepForward
    private val canStepBack: Boolean get() = inReview && session.canStepBack
    private val hintEnabled: Boolean
        get() = !inReview && (session.state == WAITING_FOR_MOVE || session.state == INCORRECT_MOVE)

    private fun emit() {
        _ui.update {
            it.copy(
                puzzleNumber = currentIndex + 1,
                puzzleCount = puzzles.size,
                displayedPosition = displayedPosition(),
                lastMove = session.lastMove,
                selectedSquare = selectedSquare,
                hintMove = hintMove,
                playerColor = session.userColor,
                isBoardFlipped = isBoardFlipped,
                sessionState = session.state,
                inReview = inReview,
                isReviewing = session.isReviewing,
                canStepForward = canStepForward,
                canStepBack = canStepBack,
                hintEnabled = hintEnabled,
                currentMoveNumber = session.currentMoveNumber,
                totalUserMoves = session.totalUserMoves,
                userRating = userRating,
                lastRatingDelta = lastRatingDelta,
                results = results.toList(),
                levelTransition = levelTransition,
                feedback = feedback(),
            )
        }
    }

    private fun feedback(): TacticsFeedback {
        if (session.state == WAITING_FOR_MOVE) {
            return if (hintMove == null) TacticsFeedback.Instruction("Find the winning move")
            else TacticsFeedback.Instruction("Move the highlighted piece to the marked square")
        }
        return when (session.state) {
            OPPONENT_MOVING -> if (session.isReviewing) TacticsFeedback.OpponentReply else TacticsFeedback.OpponentMoving
            INCORRECT_MOVE -> TacticsFeedback.IncorrectMove
            SOLVED -> if (currentIndex == puzzles.size - 1) TacticsFeedback.TrainingComplete else TacticsFeedback.PuzzleComplete
            WAITING_FOR_MOVE -> TacticsFeedback.Instruction("Find the winning move")
        }
    }

    private fun pickRandom(from: List<Puzzle>, count: Int): List<Puzzle> =
        from.shuffled().take(minOf(count, from.size))

    private companion object {
        const val NEXT_PUZZLE_DELAY_MS = 300L
        const val OPPONENT_REPLY_MS = 450L
        const val WRONG_MOVE_PREVIEW_MS = 550L
    }
}
