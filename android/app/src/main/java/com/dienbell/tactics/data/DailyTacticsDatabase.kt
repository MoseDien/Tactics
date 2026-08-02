package com.dienbell.tactics.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.dienbell.tactics.data.dao.PuzzleProgressDao
import com.dienbell.tactics.data.dao.PuzzleRecordDao
import com.dienbell.tactics.data.dao.RatingAssessmentDao
import com.dienbell.tactics.data.entity.PuzzleProgressEntity
import com.dienbell.tactics.data.entity.PuzzleRecordEntity
import com.dienbell.tactics.data.entity.RatingAssessmentEntity

@Database(
    entities = [PuzzleRecordEntity::class, PuzzleProgressEntity::class, RatingAssessmentEntity::class],
    version = 1,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class DailyTacticsDatabase : RoomDatabase() {
    abstract fun puzzleRecordDao(): PuzzleRecordDao
    abstract fun puzzleProgressDao(): PuzzleProgressDao
    abstract fun ratingAssessmentDao(): RatingAssessmentDao

    companion object {
        @Volatile private var instance: DailyTacticsDatabase? = null

        fun get(context: Context): DailyTacticsDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                DailyTacticsDatabase::class.java,
                "dailytactics.db",
            ).build().also { instance = it }
        }
    }
}
