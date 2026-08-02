package com.dienbell.tactics.data.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Singleton row recording whether the baseline rating assessment is done. */
@Entity(tableName = "rating_assessment")
data class RatingAssessmentEntity(
    @PrimaryKey val id: Int = SINGLETON_ID,
    val isCompleted: Boolean = false,
    val baselineRating: Int? = null,
) {
    companion object { const val SINGLETON_ID = 1 }
}
