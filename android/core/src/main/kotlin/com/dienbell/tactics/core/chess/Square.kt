package com.dienbell.tactics.core.chess

/**
 * A board square by 0-based file (a–h → 0–7) and rank (1–8 → 0–7).
 */
data class Square(val file: Int, val rank: Int) {

    init {
        require(file in 0..7 && rank in 0..7) { "Square out of bounds: file=$file rank=$rank" }
    }

    val notation: String
        get() = "${('a'.code + file).toChar()}${rank + 1}"

    companion object {
        /** Parses algebraic notation such as "e4"; null when malformed. */
        fun from(notation: String): Square? {
            val chars = notation.lowercase()
            if (chars.length != 2) return null
            val file = chars[0].code - 'a'.code
            val rank = chars[1].digitToIntOrNull()?.minus(1) ?: return null
            if (file !in 0..7 || rank !in 0..7) return null
            return runCatching { Square(file, rank) }.getOrNull()
        }
    }
}
