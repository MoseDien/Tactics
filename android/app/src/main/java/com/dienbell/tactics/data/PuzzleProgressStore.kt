package com.dienbell.tactics.data

import com.dienbell.tactics.data.dao.PuzzleProgressDao
import com.dienbell.tactics.data.entity.PuzzleProgressEntity

/** Main-thread-facing façade over the progress DAO. Mirrors the iOS
 *  `PuzzleProgressStore`, using get-or-create so marking never silently no-ops. */
class PuzzleProgressStore(private val dao: PuzzleProgressDao) {

    suspend fun markCompleted(puzzleId: String) {
        val now = System.currentTimeMillis()
        dao.get(puzzleId)?.let { dao.upsert(it.copy(isCompleted = true, isAttempted = true, completedAt = now)) }
            ?: dao.upsert(PuzzleProgressEntity(puzzleId, isCompleted = true, isAttempted = true, completedAt = now))
    }

    suspend fun markAttempted(puzzleId: String) {
        val existing = dao.get(puzzleId)
        if (existing != null) {
            if (!existing.isAttempted) dao.upsert(existing.copy(isAttempted = true))
        } else {
            dao.upsert(PuzzleProgressEntity(puzzleId, isAttempted = true))
        }
    }

    suspend fun markFailed(puzzleId: String) {
        val existing = dao.get(puzzleId)
        if (existing != null) {
            if (!existing.hasFailed) dao.upsert(existing.copy(hasFailed = true))
        } else {
            dao.upsert(PuzzleProgressEntity(puzzleId, hasFailed = true))
        }
    }

    suspend fun hasAttempted(puzzleId: String): Boolean = dao.get(puzzleId)?.isAttempted == true
    suspend fun isCompleted(puzzleId: String): Boolean = dao.get(puzzleId)?.isCompleted == true
    suspend fun completedCount(): Int = dao.completedCount()
    suspend fun failedCount(): Int = dao.failedCount()
    suspend fun clear() = dao.clear()
}
