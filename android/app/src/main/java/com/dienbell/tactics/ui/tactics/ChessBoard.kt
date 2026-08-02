package com.dienbell.tactics.ui.tactics

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dienbell.tactics.core.chess.ChessMove
import com.dienbell.tactics.core.chess.Piece
import com.dienbell.tactics.core.chess.PieceColor
import com.dienbell.tactics.core.chess.PieceKind
import com.dienbell.tactics.core.chess.Square
import com.dienbell.tactics.ui.theme.DarkSquare
import com.dienbell.tactics.ui.theme.LightSquare
import com.dienbell.tactics.ui.theme.MoveHighlight
import com.dienbell.tactics.ui.theme.SelectedHighlight

private val HintGreen = Color(0x6B4CAF50)
private val HintRing = Color(0xFF4CAF50)

/**
 * The 8×8 board: square colours, last-move/selected/hint highlights, coordinate
 * labels, and Unicode piece glyphs. Interaction is reported via `onSelect`.
 * Ported from the SwiftUI `ChessBoardView`.
 */
@Composable
fun ChessBoard(
    position: Map<Square, Piece>,
    selectedSquare: Square?,
    hintMove: ChessMove?,
    lastMove: ChessMove?,
    isFlipped: Boolean,
    onSelect: (Square) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ranks = remember(isFlipped) { if (isFlipped) (0..7).toList() else (7 downTo 0).toList() }
    val files = remember(isFlipped) { if (isFlipped) (7 downTo 0).toList() else (0..7).toList() }
    val bottomRank = if (isFlipped) 7 else 0
    val rightmostFile = if (isFlipped) 0 else 7

    Column(modifier = modifier.aspectRatio(1f)) {
        ranks.forEach { rank ->
            Row(Modifier.weight(1f)) {
                files.forEach { file ->
                    val square = remember(file, rank) { Square(file, rank) }
                    BoardSquare(
                        square = square,
                        piece = position[square],
                        selected = selectedSquare == square,
                        hintFrom = hintMove?.from == square,
                        hintTo = hintMove?.to == square,
                        lastMoveSquare = lastMove?.from == square || lastMove?.to == square,
                        showFileLabel = rank == bottomRank,
                        showRankLabel = file == rightmostFile,
                        modifier = Modifier
                            .weight(1f)
                            .clickable { onSelect(square) },
                    )
                }
            }
        }
    }
}

@Composable
private fun BoardSquare(
    square: Square,
    piece: Piece?,
    selected: Boolean,
    hintFrom: Boolean,
    hintTo: Boolean,
    lastMoveSquare: Boolean,
    showFileLabel: Boolean,
    showRankLabel: Boolean,
    modifier: Modifier = Modifier,
) {
    val light = (square.file + square.rank) % 2 == 0
    Box(
        modifier = modifier.background(if (light) LightSquare else DarkSquare),
        contentAlignment = Alignment.Center,
    ) {
        if (hintFrom || hintTo) Box(Modifier.fillMaxSize().background(HintGreen))
        if (lastMoveSquare) Box(Modifier.fillMaxSize().background(MoveHighlight.copy(alpha = 0.55f)))
        if (selected) Box(Modifier.fillMaxSize().background(SelectedHighlight.copy(alpha = 0.6f)))

        // Pieces fade in/out per square on each move (source empties, dest fills),
        // mirroring the iOS opacity transition.
        // Pieces fade in/out per square on each move (source empties, dest fills),
        // mirroring the iOS opacity transition.
        AnimatedContent(
            targetState = piece,
            transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(180)) },
            contentKey = { it },
            label = "piece",
        ) { p ->
            if (p != null) {
                AsyncImage(
                    model = "file:///android_asset/pieces/${p.assetKey}.svg",
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(0.88f),
                )
            }
        }

        if (hintTo) {
            Box(
                Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(Color.Transparent)
                    .padding(0.dp),
            )
        }

        CoordinateLabels(square, light, showFileLabel, showRankLabel)
    }
}

@Composable
private fun CoordinateLabels(square: Square, light: Boolean, showFile: Boolean, showRank: Boolean) {
    val labelColor = if (light) DarkSquare else LightSquare
    Box(Modifier.fillMaxSize()) {
        if (showFile) {
            Text(
                text = square.notation.take(1),
                color = labelColor,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.BottomStart).padding(2.dp),
            )
        }
        if (showRank) {
            Text(
                text = (square.rank + 1).toString(),
                color = labelColor,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(2.dp),
            )
        }
    }
}
