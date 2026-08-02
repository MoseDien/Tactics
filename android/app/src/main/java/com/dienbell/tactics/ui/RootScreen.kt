package com.dienbell.tactics.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.dienbell.tactics.core.puzzle.Puzzle
import com.dienbell.tactics.data.PuzzleProgressStore
import com.dienbell.tactics.data.PuzzleRepository
import com.dienbell.tactics.data.RatingAssessmentRepository
import com.dienbell.tactics.data.UserRatingStore
import com.dienbell.tactics.ui.rating.RatingAssessmentScreen
import com.dienbell.tactics.ui.rating.RatingAssessmentViewModel
import com.dienbell.tactics.ui.tactics.TacticsScreen
import com.dienbell.tactics.ui.tactics.TacticsViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Owns routing and the data layer wiring. Routes to Assessment on first launch
 * (or after a reassess), otherwise to Tactics with the user's tier puzzles.
 */
class RootViewModel(
    val assessmentRepo: RatingAssessmentRepository,
    val puzzleRepo: PuzzleRepository,
    val ratingStore: UserRatingStore,
    val progressStore: PuzzleProgressStore,
) : ViewModel() {

    sealed class Route {
        data object Loading : Route()
        data class Assessment(val pool: List<Puzzle>) : Route()
        data class Tactics(val dataset: List<Puzzle>) : Route()
    }

    private val _route = MutableStateFlow<Route>(Route.Loading)
    val route: StateFlow<Route> = _route.asStateFlow()

    init { viewModelScope.launch { refresh() } }

    private suspend fun refresh() {
        _route.value = if (assessmentRepo.isCompleted()) {
            val scoped = puzzleRepo.getScopedPuzzles(ratingStore.rating())
            if (scoped.isNotEmpty()) Route.Tactics(scoped) else Route.Assessment(puzzleRepo.loadAssessmentPool())
        } else {
            Route.Assessment(puzzleRepo.loadAssessmentPool())
        }
    }

    /** Imports the tier for `baseline`, saves the baseline rating, marks the
     *  assessment complete, and routes into Tactics. */
    suspend fun assessmentOnContinue(baseline: Int, onProgress: (Float) -> Unit) {
        puzzleRepo.importTier(baseline) { progress -> onProgress(progress.toFloat()) }
        ratingStore.set(baseline)
        assessmentRepo.complete(baseline)
        refresh()
    }

    fun reassess() {
        viewModelScope.launch {
            puzzleRepo.clear()
            progressStore.clear()
            assessmentRepo.clear()
            ratingStore.reset()
            refresh()
        }
    }
}

@Composable
fun RootScreen(root: RootViewModel) {
    val route by root.route.collectAsState()
    var showReassess by remember { mutableStateOf(false) }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (val r = route) {
            is RootViewModel.Route.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

            is RootViewModel.Route.Assessment -> {
                val vm: RatingAssessmentViewModel = viewModel(factory = object : ViewModelProvider.Factory {
                    override fun <T : ViewModel> create(modelClass: Class<T>): T {
                        @Suppress("UNCHECKED_CAST")
                        return RatingAssessmentViewModel(
                            pool = r.pool,
                            onContinue = { baseline, onProgress -> root.assessmentOnContinue(baseline, onProgress) },
                        ) as T
                    }
                })
                RatingAssessmentScreen(vm)
            }

            is RootViewModel.Route.Tactics -> {
                val vm: TacticsViewModel = viewModel(factory = object : ViewModelProvider.Factory {
                    override fun <T : ViewModel> create(modelClass: Class<T>): T {
                        @Suppress("UNCHECKED_CAST")
                        return TacticsViewModel(
                            dataset = r.dataset,
                            ratingStore = root.ratingStore,
                            progressStore = root.progressStore,
                            importTier = { rating -> root.puzzleRepo.importTier(rating) },
                            scopedPuzzles = { rating -> root.puzzleRepo.getScopedPuzzles(rating) },
                        ) as T
                    }
                })
                TacticsScreen(vm, onReassess = { showReassess = true })
            }
        }
    }

    if (showReassess) {
        AlertDialog(
            onDismissRequest = { showReassess = false },
            title = { Text("Reassess baseline rating?") },
            text = { Text("Your current baseline rating and puzzle progress will be cleared.") },
            confirmButton = {
                TextButton(onClick = {
                    showReassess = false
                    root.reassess()
                }) { Text("Reassess") }
            },
            dismissButton = { TextButton(onClick = { showReassess = false }) { Text("Cancel") } },
        )
    }
}
