package com.dienbell.tactics.core.chess

/**
 * A move expressed as a source/target square plus an optional promotion piece.
 */
data class ChessMove(val from: Square, val to: Square, val promotion: PieceKind? = null) {

    val uci: String
        get() {
            val suffix = promotion?.let { p ->
                when (p) {
                    PieceKind.QUEEN -> "q"
                    PieceKind.ROOK -> "r"
                    PieceKind.BISHOP -> "b"
                    PieceKind.KNIGHT -> "n"
                    else -> ""
                }
            } ?: ""
            return from.notation + to.notation + suffix
        }

    companion object {
        /** Parses a UCI string such as "e2e4" or "a7a8q"; null when malformed. */
        fun from(uci: String): ChessMove? {
            if (uci.length !in 4..5) return null
            val s = uci.lowercase()
            val from = Square.from(s.substring(0, 2)) ?: return null
            val to = Square.from(s.substring(2, 4)) ?: return null
            val promotion = if (s.length == 5) when (s[4]) {
                'q' -> PieceKind.QUEEN
                'r' -> PieceKind.ROOK
                'b' -> PieceKind.BISHOP
                'n' -> PieceKind.KNIGHT
                else -> return null
            } else null
            return ChessMove(from, to, promotion)
        }
    }
}
