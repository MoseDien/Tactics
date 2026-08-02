package com.dienbell.tactics.ui.rating

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.ui.tactics.ChessBoard
import com.dienbell.tactics.ui.tactics.PuzzleOutcome
import com.dienbell.tactics.ui.tactics.PuzzleResultRow

@Composable
fun RatingAssessmentScreen(viewModel: RatingAssessmentViewModel) {
    val ui = viewModel.ui.collectAsState().value
    LaunchedEffect(Unit) { viewModel.start() }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when {
            ui.importing -> ImportingView(ui.importProgress)
            ui.finished -> CompletionView(ui.baselineRating, viewModel::continueAssessment)
            else -> AssessmentBody(ui, viewModel)
        }
    }
}

@Composable
private fun AssessmentBody(ui: AssessmentUiState, viewModel: RatingAssessmentViewModel) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("BASELINE RATING", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Puzzle ${ui.index + 1} of ${ui.count}", style = MaterialTheme.typography.titleMedium)
        Text(
            "${if (ui.playerColor == PieceColor.WHITE) "White" else "Black"} to move",
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(12.dp))
        ChessBoard(
            position = ui.displayedPosition,
            selectedSquare = ui.selectedSquare,
            hintMove = null,
            lastMove = ui.lastMove,
            isFlipped = ui.isFlipped,
            onSelect = viewModel::select,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        PuzzleResultRow(
            outcomes = ui.results.map { if (it == true) PuzzleOutcome.CORRECT else if (it == false) PuzzleOutcome.WRONG else null },
        )
        Spacer(Modifier.height(12.dp))
        Text(
            "Solve each puzzle on your first try. ${ui.solvedCount} correct so far.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CompletionView(baseline: Int, onContinue: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Baseline rating ready", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text("Your starting rating is $baseline.", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(24.dp))
        Button(onClick = onContinue) { Text("Continue") }
    }
}

@Composable
private fun ImportingView(progress: Float) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp))
        Text("Preparing your puzzle library…", style = MaterialTheme.typography.titleMedium)
        Text("${(progress * 100).toInt()}%", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
