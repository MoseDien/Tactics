package com.dienbell.tactics.data

import android.content.Context
import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.core.rating.RatingLevel
import com.dienbell.tactics.data.dao.PuzzleRecordDao
import com.dienbell.tactics.data.entity.PuzzleRecordEntity
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reads bundled Lichess puzzle JSON (via Android's built-in `org.json`) and
 * stores/queries it through Room. JSON parsing lives here rather than in `:core`
 * so the engine stays free of any JSON dependency.
 */
class PuzzleRepository(
    private val context: Context,
    private val dao: PuzzleRecordDao,
) {
    /** Imports the 100-point tier matching `rating`, deduping by puzzle id. */
    suspend fun importTier(rating: Int, onProgress: (Double) -> Unit = {}) {
        val puzzles = parseAsset(assetFor(rating))
        val total = puzzles.size.coerceAtLeast(1)
        puzzles.chunked(BATCH).forEachIndexed { index, batch ->
            dao.insertAll(batch.map(PuzzleRecordEntity::fromDomain))
            val done = ((index + 1) * BATCH).coerceAtMost(total)
            onProgress(done.toDouble() / total)
        }
    }

    suspend fun getScopedPuzzles(rating: Int): List<Puzzle> {
        val level = RatingLevel(rating)
        return dao.getForRatingRange(level.lowerBound, level.upperBound).map { it.toDomain() }
    }

    suspend fun loadAssessmentPool(): List<Puzzle> = parseAsset("puzzles/rating_puzzles.json")

    suspend fun count(): Int = dao.count()
    suspend fun clear() = dao.clear()

    private fun assetFor(rating: Int): String = "puzzles/${RatingLevel(rating).rawValue}.json"

    private fun parseAsset(path: String): List<Puzzle> {
        val json = context.assets.open(path).bufferedReader().use { it.readText() }
        val array = JSONArray(json)
        return List(array.length()) { i -> array.getJSONObject(i).toPuzzle() }
    }

    private fun JSONObject.toPuzzle(): Puzzle = Puzzle(
        id = getString("id"),
        fen = getString("fen"),
        moves = getJSONArray("moves").toStringList(),
        rating = optNullableInt("rating"),
        themes = getJSONArray("themes").toStringList(),
        ratingDeviation = optNullableInt("ratingDeviation"),
        popularity = optNullableInt("popularity"),
        playCount = optNullableInt("playCount"),
        gameUrl = optNullableString("gameUrl"),
        openingTags = optJSONArray("openingTags")?.toStringList(),
    )

    private fun JSONObject.optNullableInt(key: String): Int? =
        if (has(key) && !isNull(key)) getInt(key) else null

    private fun JSONObject.optNullableString(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null

    private fun JSONArray.toStringList(): List<String> = List(length()) { getString(it) }

    private companion object { const val BATCH = 250 }
}
