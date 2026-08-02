package com.dienbell.tactics.core.chess

import kotlin.math.abs

/**
 * A chess position: piece placement plus the side to move. FEN castling/en
 * passant/halfmove counters are intentionally not modelled — only piece
 * placement and side to move are parsed, matching the iOS engine.
 */
class Board private constructor(
    initialPieces: Map<Square, Piece>,
    val sideToMove: PieceColor,
) {
    var pieces: Map<Square, Piece> = initialPieces
        private set

    sealed class FENError(message: String) : Exception(message) {
        data object MissingFields : FENError("FEN is missing fields")
        data object InvalidRankCount : FENError("FEN has an invalid rank count")
        class InvalidRank(rank: String) : FENError("FEN has an invalid rank: $rank")
        class InvalidPiece(piece: Char) : FENError("FEN has an invalid piece: $piece")
        class InvalidSideToMove(side: String) : FENError("FEN has an invalid side to move: $side")
    }

    /** Applies `move` (with castling, en passant, promotion). Returns false if no
     *  piece sits on the origin square. */
    fun apply(move: ChessMove): Boolean {
        val moving = pieces[move.from] ?: return false
        val board = pieces.toMutableMap()
        board.remove(move.from)
        val targetWasEmpty = board[move.to] == null
        val resultingKind = move.promotion ?: moving.kind
        board[move.to] = Piece(moving.color, resultingKind)

        // Castling: a king advancing two files also relocates the corner rook.
        if (moving.kind == PieceKind.KING && abs(move.to.file - move.from.file) == 2) {
            val rank = move.from.rank
            when (move.to.file) {
                6 -> board.remove(Square(7, rank))?.let { rook -> board[Square(5, rank)] = rook }
                2 -> board.remove(Square(0, rank))?.let { rook -> board[Square(3, rank)] = rook }
            }
        }

        // En passant: a pawn moving diagonally onto an empty square captures the
        // enemy pawn that just advanced beside its origin.
        if (moving.kind == PieceKind.PAWN && move.from.file != move.to.file && targetWasEmpty) {
            board.remove(Square(move.to.file, move.from.rank))
        }

        pieces = board
        return true
    }

    /** Basic piece-movement legality for `mover`: shape, blocking, self-capture.
     *  Does not cover check/pin, castling, en passant, or promotion. */
    fun isLegal(move: ChessMove, mover: PieceColor): Boolean {
        val piece = pieces[move.from] ?: return false
        if (piece.color != mover) return false
        val occupant = pieces[move.to]
        if (occupant != null && occupant.color == mover) return false
        return shapeIsLegal(piece, move.from, move.to)
    }

    private fun shapeIsLegal(piece: Piece, from: Square, to: Square): Boolean {
        val df = to.file - from.file
        val dr = to.rank - from.rank
        if (df == 0 && dr == 0) return false
        return when (piece.kind) {
            PieceKind.KNIGHT ->
                (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1)
            PieceKind.BISHOP ->
                abs(df) == abs(dr) && pathIsClear(from, to)
            PieceKind.ROOK ->
                (df == 0 || dr == 0) && pathIsClear(from, to)
            PieceKind.QUEEN ->
                (df == 0 || dr == 0 || abs(df) == abs(dr)) && pathIsClear(from, to)
            PieceKind.KING ->
                maxOf(abs(df), abs(dr)) == 1
            PieceKind.PAWN ->
                pawnShapeIsLegal(piece, from, to)
        }
    }

    private fun pawnShapeIsLegal(pawn: Piece, from: Square, to: Square): Boolean {
        val df = to.file - from.file
        val dr = to.rank - from.rank
        val direction = if (pawn.color == PieceColor.WHITE) 1 else -1
        val startRank = if (pawn.color == PieceColor.WHITE) 1 else 6

        if (df == 0) {
            if (dr == direction && pieces[to] == null) return true
            if (from.rank == startRank && dr == 2 * direction) {
                val middle = Square(from.file, from.rank + direction)
                return pieces[to] == null && pieces[middle] == null
            }
            return false
        }
        if (abs(df) == 1 && dr == direction) {
            return pieces[to]?.color == pawn.color.opponent
        }
        return false
    }

    private fun pathIsClear(from: Square, to: Square): Boolean {
        val sf = signum(to.file - from.file)
        val sr = signum(to.rank - from.rank)
        var file = from.file + sf
        var rank = from.rank + sr
        while (file != to.file || rank != to.rank) {
            if (pieces[Square(file, rank)] != null) return false
            file += sf
            rank += sr
        }
        return true
    }

    private fun signum(x: Int): Int = when {
        x > 0 -> 1
        x < 0 -> -1
        else -> 0
    }

    companion object {
        fun parse(fen: String): Board {
            val fields = fen.split(" ")
            if (fields.size < 2) throw FENError.MissingFields

            val ranks = fields[0].split("/")
            if (ranks.size != 8) throw FENError.InvalidRankCount

            val pieces = mutableMapOf<Square, Piece>()
            for ((rankIndex, encodedRank) in ranks.withIndex()) {
                var file = 0
                for (ch in encodedRank) {
                    val empty = ch.digitToIntOrNull()
                    if (empty != null) {
                        if (empty !in 1..8) throw FENError.InvalidRank(encodedRank)
                        file += empty
                    } else {
                        if (file >= 8) throw FENError.InvalidPiece(ch)
                        val piece = pieceFor(ch) ?: throw FENError.InvalidPiece(ch)
                        pieces[Square(file, 7 - rankIndex)] = piece
                        file += 1
                    }
                }
                if (file != 8) throw FENError.InvalidRank(encodedRank)
            }

            val sideToMove = when (fields[1]) {
                "w" -> PieceColor.WHITE
                "b" -> PieceColor.BLACK
                else -> throw FENError.InvalidSideToMove(fields[1])
            }
            return Board(pieces, sideToMove)
        }

        private fun pieceFor(ch: Char): Piece? {
            val color = if (ch.isUpperCase()) PieceColor.WHITE else PieceColor.BLACK
            val kind = when (ch.lowercaseChar()) {
                'k' -> PieceKind.KING
                'q' -> PieceKind.QUEEN
                'r' -> PieceKind.ROOK
                'b' -> PieceKind.BISHOP
                'n' -> PieceKind.KNIGHT
                'p' -> PieceKind.PAWN
                else -> return null
            }
            return Piece(color, kind)
        }
    }
}
