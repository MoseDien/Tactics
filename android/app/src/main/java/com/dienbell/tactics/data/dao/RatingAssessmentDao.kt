package com.dienbell.tactics.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.dienbell.tactics.data.entity.RatingAssessmentEntity

@Dao
interface RatingAssessmentDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: RatingAssessmentEntity)

    @Query("SELECT * FROM rating_assessment WHERE id = ${RatingAssessmentEntity.SINGLETON_ID}")
    suspend fun get(): RatingAssessmentEntity?

    @Query("DELETE FROM rating_assessment")
    suspend fun clear()
}
