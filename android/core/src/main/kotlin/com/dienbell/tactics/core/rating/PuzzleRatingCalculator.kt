package com.dienbell.tactics.core.rating

import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Elo-style rating update for a single solved/failed puzzle.
 */
class PuzzleRatingCalculator(private val kFactor: Double = 32.0) {

    fun expectedScore(userRating: Int, puzzleRating: Int): Double =
        1.0 / (1.0 + 10.0.pow((puzzleRating - userRating) / 400.0))

    fun change(userRating: Int, puzzleRating: Int, solved: Boolean): Int {
        val expected = expectedScore(userRating, puzzleRating)
        val actual = if (solved) 1.0 else 0.0
        val delta = (kFactor * (actual - expected)).roundToInt()
        // A solved puzzle never yields a zero/negative delta; a failed one never zero/positive.
        return if (delta == 0) if (solved) 1 else -1 else delta
    }
}
