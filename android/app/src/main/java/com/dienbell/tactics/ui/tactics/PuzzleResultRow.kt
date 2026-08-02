package com.dienbell.tactics.ui.tactics

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A horizontal row of per-puzzle markers shown below the board — shared by the
 * daily round and the rating assessment so both screens read identically:
 * green ✓ correct, gray ✓ not yet attempted, soft-red ✗ a wrong move was made.
 */
@Composable
fun PuzzleResultRow(
    outcomes: List<PuzzleOutcome?>,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        outcomes.forEach { outcome ->
            val (symbol, color) = when (outcome) {
                PuzzleOutcome.CORRECT -> "✓" to Color(0xFF2E7D32)
                PuzzleOutcome.WRONG -> "✕" to Color(0xFFE57373)
                null -> "✓" to Color(0xFFB0B0B0)
            }
            Text(
                text = symbol,
                color = color,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}
