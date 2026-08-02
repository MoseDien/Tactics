package com.dienbell.tactics.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** Runtime/user state for a puzzle. `isAttempted` carries a column default so
 *  future schema changes don't trip the same migration failure the iOS app had. */
@Entity(tableName = "puzzle_progress")
data class PuzzleProgressEntity(
    @PrimaryKey val puzzleId: String,
    @ColumnInfo(name = "isCompleted") val isCompleted: Boolean = false,
    @ColumnInfo(name = "isAttempted", defaultValue = "0") val isAttempted: Boolean = false,
    @ColumnInfo(name = "hasFailed", defaultValue = "0") val hasFailed: Boolean = false,
    val completedAt: Long? = null,
)
