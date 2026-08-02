package com.dienbell.tactics.core.chess

enum class PieceColor {
    WHITE, BLACK;

    /** The side that moves next against this one. */
    val opponent: PieceColor get() = if (this == WHITE) BLACK else WHITE
}

enum class PieceKind { KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN }

/**
 * A coloured piece. Pure value type — no SwiftUI/Android dependencies.
 */
data class Piece(val color: PieceColor, val kind: PieceKind) {

    /** Asset key matching the bundled chessnut SVGs, e.g. "wK", "bP". */
    val assetKey: String
        get() = "${if (color == PieceColor.WHITE) "w" else "b"}${kind.symbol}"

    companion object {
        private val PieceKind.symbol: Char
            get() = when (this) {
                PieceKind.KING -> 'K'
                PieceKind.QUEEN -> 'Q'
                PieceKind.ROOK -> 'R'
                PieceKind.BISHOP -> 'B'
                PieceKind.KNIGHT -> 'N'
                PieceKind.PAWN -> 'P'
            }
    }
}
