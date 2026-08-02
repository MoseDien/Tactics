package com.dienbell.tactics.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.dienbell.tactics.data.entity.PuzzleProgressEntity

@Dao
interface PuzzleProgressDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(progress: PuzzleProgressEntity)

    @Query("SELECT * FROM puzzle_progress WHERE puzzleId = :id")
    suspend fun get(id: String): PuzzleProgressEntity?

    @Query("SELECT COUNT(*) FROM puzzle_progress WHERE isCompleted = 1")
    suspend fun completedCount(): Int

    @Query("SELECT COUNT(*) FROM puzzle_progress WHERE hasFailed = 1")
    suspend fun failedCount(): Int

    @Query("DELETE FROM puzzle_progress")
    suspend fun clear()
}
