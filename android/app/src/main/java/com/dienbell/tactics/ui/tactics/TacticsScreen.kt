package com.dienbell.tactics.ui.tactics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dienbell.tactics.core.chess.PieceColor

@Composable
fun TacticsScreen(
    viewModel: TacticsViewModel,
    modifier: Modifier = Modifier,
    onReassess: () -> Unit = {},
) {
    val ui = viewModel.ui.collectAsState().value

    // Kick off the opening machine move when the screen first appears.
    LaunchedEffect(Unit) { viewModel.start() }

    ui.levelTransition?.let { level ->
        LevelTransitionDialog(
            rating = ui.userRating,
            levelLabel = level.rawValue,
            onConfirm = viewModel::confirmLevelTransition,
        )
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                OutlinedButton(onClick = onReassess) { Text("Reassess") }
            }
            Spacer(Modifier.height(4.dp))
            Header(ui)
            Spacer(Modifier.height(8.dp))
            ChessBoard(
                position = ui.displayedPosition,
                selectedSquare = ui.selectedSquare,
                hintMove = ui.hintMove,
                lastMove = ui.lastMove,
                isFlipped = ui.isBoardFlipped,
                onSelect = viewModel::select,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            PuzzleResultRow(outcomes = ui.results)
            Spacer(Modifier.height(8.dp))
            RatingPanel(ui)
            Spacer(Modifier.height(8.dp))
            MoveControls(viewModel = viewModel, ui = ui)
            Spacer(Modifier.height(12.dp))
            Feedback(ui, viewModel)
        }
    }
}

@Composable
private fun Header(ui: TacticsUiState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            "PUZZLE ${ui.puzzleNumber} OF ${ui.puzzleCount}",
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
        val title = if (ui.sessionState == com.dienbell.tactics.core.puzzle.PuzzleSessionState.SOLVED) "Puzzle complete!" else "Your turn"
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(
            "Find the best move for ${if (ui.playerColor == PieceColor.WHITE) "white" else "black"}.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun RatingPanel(ui: TacticsUiState) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Rating", style = MaterialTheme.typography.titleMedium)
        Text("${ui.userRating}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        ui.lastRatingDelta?.let { delta ->
            val positive = delta >= 0
            Text(
                if (positive) "+$delta" else "$delta",
                color = if (positive) Color(0xFF2E7D32) else Color(0xFFC62828),
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .wrapContentSize()
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun MoveControls(viewModel: TacticsViewModel, ui: TacticsUiState) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(onClick = viewModel::toggleBoardFlip) { Text("⇅") }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = viewModel::stepBack, enabled = ui.canStepBack) { Text("‹") }
            Text("${ui.currentMoveNumber} / ${ui.totalUserMoves}", fontWeight = FontWeight.SemiBold)
            OutlinedButton(onClick = viewModel::stepForward, enabled = ui.canStepForward) { Text("›") }
        }
        OutlinedButton(onClick = viewModel::requestHint, enabled = ui.hintEnabled) { Text("Hint") }
    }
}

@Composable
private fun Feedback(ui: TacticsUiState, viewModel: TacticsViewModel) {
    val message = when (val f = ui.feedback) {
        is TacticsFeedback.Instruction -> f.message
        is TacticsFeedback.Error -> f.message
        TacticsFeedback.OpponentMoving -> "Opponent is moving…"
        TacticsFeedback.OpponentReply -> "Opponent's reply"
        TacticsFeedback.IncorrectMove -> "Not quite — look for a forcing move."
        TacticsFeedback.Reviewing -> "Reviewing move ${ui.currentMoveNumber} / ${ui.totalUserMoves}"
        TacticsFeedback.PuzzleComplete -> "Puzzle complete!"
        TacticsFeedback.TrainingComplete -> "Training complete!"
    }
    Text(
        message,
        style = MaterialTheme.typography.bodyMedium,
        color = when (ui.feedback) {
            is TacticsFeedback.Error -> Color(0xFFC62828)
            TacticsFeedback.IncorrectMove -> Color(0xFFEF6C00)
            TacticsFeedback.PuzzleComplete, TacticsFeedback.TrainingComplete -> Color(0xFF2E7D32)
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        },
    )

    if (ui.sessionState == com.dienbell.tactics.core.puzzle.PuzzleSessionState.SOLVED) {
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = viewModel::restart) { Text("Play again") }
            if (ui.isBatchComplete) {
                Button(onClick = viewModel::restartBatch) { Text("Start over") }
            } else {
                Button(onClick = viewModel::nextPuzzle) { Text("Next puzzle") }
            }
        }
    }
}

@Composable
private fun LevelTransitionDialog(rating: Int, levelLabel: String, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onConfirm,
        title = { Text("New rating level") },
        text = { Text("Your rating is now $rating, so your level is $levelLabel.") },
        confirmButton = {
            Button(onClick = onConfirm) { Text("Load $levelLabel puzzles") }
        },
    )
}
