package com.dienbell.tactics.data

import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.data.dao.RatingAssessmentDao
import com.dienbell.tactics.data.entity.RatingAssessmentEntity

/** Records the baseline-assessment completion state. */
class RatingAssessmentRepository(private val dao: RatingAssessmentDao) {
    suspend fun isCompleted(): Boolean = dao.get()?.isCompleted == true
    suspend fun baselineRating(): Int? = dao.get()?.baselineRating

    suspend fun complete(baselineRating: Int) {
        dao.upsert(RatingAssessmentEntity(isCompleted = true, baselineRating = baselineRating))
    }

    suspend fun clear() = dao.clear()
}

/** Picks `count` puzzles of varying difficulty from the assessment pool, and
 *  derives the baseline rating from average difficulty + solve performance. */
object RatingAssessmentPlan {

    fun select(pool: List<Puzzle>, count: Int): List<Puzzle> {
        val sorted = pool.sortedBy { it.rating ?: 1500 }
        if (sorted.size <= count) return sorted
        val step = sorted.size.toDouble() / count
        return List(count) { i -> sorted[(i * step).toInt().coerceAtMost(sorted.lastIndex)] }
    }

    fun baselineRating(puzzles: List<Puzzle>, solved: Int): Int {
        val ratings = puzzles.mapNotNull { it.rating }
        val average = if (ratings.isEmpty()) 1500 else ratings.average().toInt()
        val performance = ((solved.toDouble() / puzzles.size.coerceAtLeast(1) - 0.5) * 400).toInt()
        return (average + performance).coerceIn(400, 2400)
    }
}
