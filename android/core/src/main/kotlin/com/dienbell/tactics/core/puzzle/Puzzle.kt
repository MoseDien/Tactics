package com.dienbell.tactics.core.puzzle

/**
 * Recognised Lichess theme tags. Lichess JSON may carry tags not listed here
 * (e.g. "mateIn2"); decoding keeps themes as raw strings and maps the known
 * ones, so unknown tags are simply dropped rather than failing the decode.
 */
enum class PuzzleTheme {
    FORK, PIN, SKEWER, DISCOVERED_ATTACK, SACRIFICE, MATE,
    DEFENSIVE_MOVE, ENDGAME, ADVANTAGE, MIDDLEGAME, ROOK_ENDGAME, SHORT;

    companion object {
        fun fromRaw(raw: String): PuzzleTheme? = when (raw) {
            "fork" -> FORK
            "pin" -> PIN
            "skewer" -> SKEWER
            "discoveredAttack" -> DISCOVERED_ATTACK
            "sacrifice" -> SACRIFICE
            "mate" -> MATE
            "defensiveMove" -> DEFENSIVE_MOVE
            "endgame" -> ENDGAME
            "advantage" -> ADVANTAGE
            "middlegame" -> MIDDLEGAME
            "rookEndgame" -> ROOK_ENDGAME
            "short" -> SHORT
            else -> null
        }
    }
}

/**
 * A Lichess puzzle. `themes` is stored as raw strings (lenient) to match the
 * iOS importer; optional metadata is nullable so datasets without it still decode.
 */
/**
 * A Lichess puzzle. `themes` is stored as raw strings (lenient) to match the
 * iOS importer; optional metadata is nullable so datasets without it still parse.
 * Plain data class — JSON parsing lives in the app layer (`org.json`).
 */
data class Puzzle(
    val id: String,
    val fen: String,
    val moves: List<String>,
    val rating: Int? = null,
    val themes: List<String> = emptyList(),
    val ratingDeviation: Int? = null,
    val popularity: Int? = null,
    val playCount: Int? = null,
    val gameUrl: String? = null,
    val openingTags: List<String>? = null,
) {
    val recognisedThemes: List<PuzzleTheme>
        get() = themes.mapNotNull(PuzzleTheme::fromRaw)

    companion object {
        val SAMPLES: List<Puzzle> = listOf(
            Puzzle(
                id = "sample-001",
                fen = "r3k2r/p1pp1p1p/b1p3p1/3nP3/1bP5/NP6/P3QPPP/R3KB1R w KQkq - 1",
                moves = listOf("e1d1", "d5c3", "d1c2", "c3e2"),
                rating = 1017,
                themes = listOf("sacrifice", "mate"),
            ),
            Puzzle(
                id = "sample-002",
                fen = "r2qr1k1/b1p2ppp/pp4n1/P1P1p3/4P1n1/B2P2Pb/3NBP1P/RN1QR1K1 b",
                moves = listOf("b6c5", "e2g4", "h3g4", "d1g4"),
                rating = 1084,
                themes = listOf("advantage", "middlegame", "short"),
            ),
            Puzzle(
                id = "sample-003",
                fen = "8/4R3/1p2P3/p4r2/P6p/1P3Pk1/4K3/8 w - - 1 64",
                moves = listOf("e7f7", "f5e5", "e2f1", "e5e6"),
                rating = 1383,
                themes = listOf("advantage", "endgame", "rookEndgame", "short"),
            ),
        )
    }
}
