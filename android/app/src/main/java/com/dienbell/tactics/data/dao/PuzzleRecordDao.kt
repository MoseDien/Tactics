package com.dienbell.tactics.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.dienbell.tactics.data.entity.PuzzleRecordEntity

@Dao
interface PuzzleRecordDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(puzzles: List<PuzzleRecordEntity>)

    @Query("SELECT * FROM puzzle_record WHERE rating >= :min AND rating < :max")
    suspend fun getForRatingRange(min: Int, max: Int): List<PuzzleRecordEntity>

    @Query("SELECT COUNT(*) FROM puzzle_record")
    suspend fun count(): Int

    @Query("DELETE FROM puzzle_record")
    suspend fun clear()
}
