package com.dienbell.tactics.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.dienbell.tactics.core.puzzle.Puzzle

/** Persisted static content of a puzzle (the bundled data is read-only). */
@Entity(
    tableName = "puzzle_record",
    indices = [Index(value = ["puzzleId"], unique = true)],
)
data class PuzzleRecordEntity(
    @PrimaryKey val puzzleId: String,
    val fen: String,
    val moves: List<String>,
    val rating: Int,
    val ratingDeviation: Int?,
    val popularity: Int?,
    val playCount: Int?,
    val themes: List<String>,
    val gameUrl: String?,
    val openingTags: List<String>?,
) {
    fun toDomain(): Puzzle = Puzzle(
        id = puzzleId,
        fen = fen,
        moves = moves,
        rating = rating,
        themes = themes,
        ratingDeviation = ratingDeviation,
        popularity = popularity,
        playCount = playCount,
        gameUrl = gameUrl,
        openingTags = openingTags,
    )

    companion object {
        fun fromDomain(p: Puzzle) = PuzzleRecordEntity(
            puzzleId = p.id,
            fen = p.fen,
            moves = p.moves,
            rating = p.rating ?: 1500,
            ratingDeviation = p.ratingDeviation,
            popularity = p.popularity,
            playCount = p.playCount,
            themes = p.themes,
            gameUrl = p.gameUrl,
            openingTags = p.openingTags,
        )
    }
}
