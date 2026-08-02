package com.dienbell.tactics

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.dienbell.tactics.data.DailyTacticsDatabase
import com.dienbell.tactics.data.PuzzleProgressStore
import com.dienbell.tactics.data.PuzzleRepository
import com.dienbell.tactics.data.RatingAssessmentRepository
import com.dienbell.tactics.data.UserRatingStore
import com.dienbell.tactics.ui.RootScreen
import com.dienbell.tactics.ui.RootViewModel
import com.dienbell.tactics.ui.theme.DailyTacticsTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            DailyTacticsTheme {
                val context = LocalContext.current
                val root: RootViewModel = viewModel(factory = object : ViewModelProvider.Factory {
                    override fun <T : ViewModel> create(modelClass: Class<T>): T {
                        val db = DailyTacticsDatabase.get(context)
                        @Suppress("UNCHECKED_CAST")
                        return RootViewModel(
                            assessmentRepo = RatingAssessmentRepository(db.ratingAssessmentDao()),
                            puzzleRepo = PuzzleRepository(context, db.puzzleRecordDao()),
                            ratingStore = UserRatingStore(context),
                            progressStore = PuzzleProgressStore(db.puzzleProgressDao()),
                        ) as T
                    }
                })
                RootScreen(root)
            }
        }
    }
}
