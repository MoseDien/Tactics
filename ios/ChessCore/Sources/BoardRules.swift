import Foundation

extension Board {
    /// Whether `move` is a legal chess move for `mover`: movement shape, path
    /// blocking, self-capture, check and pin legality, castling, en passant,
    /// and promotion requirements. Trusted puzzle-line moves that involve
    /// unusual data still flow through `apply`, which remains unchecked.
    public func isLegal(_ move: ChessMove, for mover: PieceColor) -> Bool {
        guard let piece = pieces[move.from], piece.color == mover else { return false }
        if let occupant = pieces[move.to], occupant.color == mover { return false }

        // Pawn pushes and captures onto the last rank must promote, and the
        // promotion piece must be one a pawn can promote to.
        if piece.kind == .pawn, move.to.rank == 0 || move.to.rank == 7 {
            guard let promotion = move.promotion,
                  promotion == .queen || promotion == .rook || promotion == .bishop || promotion == .knight
            else { return false }
        } else if move.promotion != nil {
            return false
        }

        // Castling: a king advancing two files. King-shape validation would
        // reject it, so it has its own full rule here.
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            return castleIsLegal(move, for: mover)
        }

        guard Self.shapeIsLegal(piece, from: move.from, to: move.to, in: pieces)
            || enPassantShapeApplies(piece, to: move.to)
        else { return false }

        // The mover's own king may not be left attacked (covers pins and
        // moving into check). En-passant captures expose the king along the
        // rank in rare positions, so the candidate position is always tested.
        var candidate = self
        guard candidate.applyUncheckedForLegality(move) else { return false }
        let kingSquare = candidate.kingSquare(of: mover, in: candidate.pieces)
            ?? kingSquare(of: mover, in: pieces)
        return !Self.isAttacked(
            kingSquare,
            by: mover.opponent,
            in: candidate.pieces,
            enPassantTarget: nil
        )
    }

    /// En passant target squares are empty, so the pawn diagonal-capture shape
    /// does not apply. This recognizes the shape when the FEN's en-passant
    /// field matches the destination.
    private func enPassantShapeApplies(_ pawn: Piece, to target: Square) -> Bool {
        pawn.kind == .pawn && enPassantTarget == target
    }

    /// Full castling rule: rights, empty path, unattacked path (including the
    /// king's origin and destination).
    private func castleIsLegal(_ move: ChessMove, for mover: PieceColor) -> Bool {
        let kingSide = move.to.file == 6
        let backRank = mover == .white ? 0 : 7
        guard move.from == Square(file: 4, rank: backRank)! else { return false }

        let rights: CastlingRights = kingSide
            ? (mover == .white ? .whiteKingSide : .blackKingSide)
            : (mover == .white ? .whiteQueenSide : .blackQueenSide)
        guard castlingRights.contains(rights) else { return false }

        let rookFile = kingSide ? 7 : 0
        guard pieces[Square(file: rookFile, rank: backRank)!] == Piece(color: mover, kind: .rook) else { return false }

        let pathFiles = kingSide ? [5, 6] : [1, 2, 3]
        for file in pathFiles where pieces[Square(file: file, rank: backRank)!] != nil {
            return false
        }
        // The king may not castle out of, through, or into check.
        let checkedFiles = kingSide ? [4, 5, 6] : [4, 3, 2]
        for file in checkedFiles
        where Self.isAttacked(
            Square(file: file, rank: backRank)!,
            by: mover.opponent,
            in: pieces,
            enPassantTarget: nil
        ) {
            return false
        }
        return true
    }

    static func shapeIsLegal(
        _ piece: Piece,
        from: Square,
        to: Square,
        in pieces: [Square: Piece]
    ) -> Bool {
        let fileDelta = to.file - from.file
        let rankDelta = to.rank - from.rank
        guard fileDelta != 0 || rankDelta != 0 else { return false }

        switch piece.kind {
        case .knight:
            return (abs(fileDelta), abs(rankDelta)) == (1, 2)
                || (abs(fileDelta), abs(rankDelta)) == (2, 1)
        case .bishop:
            return abs(fileDelta) == abs(rankDelta) && pathIsClear(from: from, to: to, in: pieces)
        case .rook:
            return (fileDelta == 0 || rankDelta == 0) && pathIsClear(from: from, to: to, in: pieces)
        case .queen:
            let straight = fileDelta == 0 || rankDelta == 0
            let diagonal = abs(fileDelta) == abs(rankDelta)
            return (straight || diagonal) && pathIsClear(from: from, to: to, in: pieces)
        case .king:
            return max(abs(fileDelta), abs(rankDelta)) == 1
        case .pawn:
            return pawnShapeIsLegal(piece, from: from, to: to, in: pieces)
        }
    }

    private static func pawnShapeIsLegal(
        _ pawn: Piece,
        from: Square,
        to: Square,
        in pieces: [Square: Piece]
    ) -> Bool {
        let fileDelta = to.file - from.file
        let rankDelta = to.rank - from.rank
        let direction = pawn.color == .white ? 1 : -1
        let startRank = pawn.color == .white ? 1 : 6

        // Forward push: one square, or two from the starting rank. Target must be empty.
        if fileDelta == 0 {
            if rankDelta == direction, pieces[to] == nil { return true }
            if from.rank == startRank, rankDelta == 2 * direction {
                let middle = Square(file: from.file, rank: from.rank + direction)!
                return pieces[to] == nil && pieces[middle] == nil
            }
            return false
        }
        // Diagonal capture: one file over, one rank forward, onto an enemy
        // piece. The en-passant exception (empty target) is handled by the
        // caller, which knows the FEN's en-passant field.
        if abs(fileDelta) == 1, rankDelta == direction {
            return pieces[to]?.color == pawn.color.opponent
        }
        return false
    }

    /// Whether `move` sends a pawn of `mover` to its promotion rank. The UI
    /// uses this to ask which piece to promote to.
    public func isPromotion(_ move: ChessMove, for mover: PieceColor) -> Bool {
        guard let piece = pieces[move.from], piece.color == mover, piece.kind == .pawn else { return false }
        return move.to.rank == 0 || move.to.rank == 7
    }

    private static func pathIsClear(from: Square, to: Square, in pieces: [Square: Piece]) -> Bool {
        let stepFile = (to.file - from.file).signum()
        let stepRank = (to.rank - from.rank).signum()
        var file = from.file + stepFile
        var rank = from.rank + stepRank
        while file != to.file || rank != to.rank {
            if pieces[Square(file: file, rank: rank)!] != nil { return false }
            file += stepFile
            rank += stepRank
        }
        return true
    }
}
