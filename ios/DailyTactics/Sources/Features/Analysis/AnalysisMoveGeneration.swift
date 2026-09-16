import Foundation

extension Analysis.Position {
    // MARK: - Generation

    func pseudoLegalMoves(from square: Analysis.Square) -> [Analysis.Move] {
        guard let piece = self[square] else { return [] }
        switch piece.kind {
        case .pawn: return pawnMoves(from: square, color: piece.color)
        case .knight: return stepMoves(from: square, color: piece.color, offsets: Analysis.knightOffsets)
        case .king: return kingMoves(from: square, color: piece.color)
        case .bishop: return rayMoves(from: square, color: piece.color, directions: Analysis.diagonalDirections)
        case .rook: return rayMoves(from: square, color: piece.color, directions: Analysis.orthogonalDirections)
        case .queen:
            return rayMoves(from: square, color: piece.color, directions: Analysis.diagonalDirections + Analysis.orthogonalDirections)
        }
    }

    func legalMoves(from square: Analysis.Square) -> [Analysis.Move] {
        guard let piece = self[square], piece.color == activeColor else { return [] }
        return pseudoLegalMoves(from: square).filter(isLegal)
    }

    func legalMoves(for color: Analysis.Color) -> [Analysis.Move] {
        guard color == activeColor else { return [] }
        var moves: [Analysis.Move] = []
        for index in 0..<64 where squares[index]?.color == color {
            if let square = Analysis.Square(index: index) {
                moves.append(contentsOf: pseudoLegalMoves(from: square).filter(isLegal))
            }
        }
        return moves
    }

    /// Make on a copy and require the mover's king to be safe: covers pins,
    /// en-passant self-check, and king walks into attack in one rule.
    func isLegal(_ move: Analysis.Move) -> Bool {
        guard let mover = self[move.from], mover.color == activeColor else { return false }
        let next = applying(move)
        if let king = next.kingSquare(of: mover.color) {
            return !next.isAttacked(king, by: mover.color.opposite)
        }
        return true
    }

    // MARK: - Applying

    func applying(_ move: Analysis.Move) -> Analysis.Position {
        var next = self
        guard let mover = self[move.from] else { return next }
        let captured = self[move.to]

        let isCapture = captured != nil
            || (mover.kind == .pawn && move.to == enPassantTarget && self[move.to] == nil)
        if mover.kind == .pawn || isCapture {
            next.halfmoveClock = 0
        } else {
            next.halfmoveClock += 1
        }

        if let promotion = move.promotion {
            next[move.to] = Analysis.Piece(color: mover.color, kind: promotion)
        } else {
            next[move.to] = mover
        }
        next[move.from] = nil

        // En-passant capture removes the pawn that just double-pushed; both
        // coordinates come from existing squares, so the force-unwrap is safe.
        if mover.kind == .pawn, move.to == enPassantTarget, self[move.to] == nil {
            next[Analysis.Square(file: move.to.file, rank: move.from.rank)!] = nil
        }

        // Castling: a two-file king hop relocates its rook.
        if mover.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6 {
                next[Analysis.Square(file: 5, rank: rank)!] = self[Analysis.Square(file: 7, rank: rank)!]
                next[Analysis.Square(file: 7, rank: rank)!] = nil
            } else if move.to.file == 2 {
                next[Analysis.Square(file: 3, rank: rank)!] = self[Analysis.Square(file: 0, rank: rank)!]
                next[Analysis.Square(file: 0, rank: rank)!] = nil
            }
        }

        if mover.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassantTarget = Analysis.Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            next.enPassantTarget = nil
        }

        if mover.kind == .king {
            if mover.color == .white {
                next.castling.subtract([.whiteKingSide, .whiteQueenSide])
            } else {
                next.castling.subtract([.blackKingSide, .blackQueenSide])
            }
        }
        if mover.kind == .rook {
            next.castling.subtract(rookRights(for: move.from, color: mover.color))
        }
        if captured?.kind == .rook, captured?.color != mover.color {
            next.castling.subtract(rookRights(for: move.to, color: captured!.color))
        }

        next.activeColor = activeColor.opposite
        if activeColor == .black {
            next.fullmoveNumber += 1
        }
        return next
    }

    // MARK: - Per-kind helpers

    private func rookRights(for square: Analysis.Square, color: Analysis.Color) -> Analysis.CastlingRights {
        var rights: Analysis.CastlingRights = []
        if square.rank == 0 {
            if square.file == 0 && color == .white { rights.insert(.whiteQueenSide) }
            if square.file == 7 && color == .white { rights.insert(.whiteKingSide) }
        }
        if square.rank == 7 {
            if square.file == 0 && color == .black { rights.insert(.blackQueenSide) }
            if square.file == 7 && color == .black { rights.insert(.blackKingSide) }
        }
        return rights
    }

    private func pawnMoves(from square: Analysis.Square, color: Analysis.Color) -> [Analysis.Move] {
        var moves: [Analysis.Move] = []
        let direction = color == .white ? 1 : -1
        let promotionRank = color == .white ? 7 : 0
        let startRank = color == .white ? 1 : 6

        func appendPromotions(to target: Analysis.Square) {
            for kind in [Analysis.PieceKind.queen, .rook, .bishop, .knight] {
                moves.append(Analysis.Move(from: square, to: target, promotion: kind))
            }
        }

        if let single = Analysis.Square(file: square.file, rank: square.rank + direction), self[single] == nil {
            if single.rank == promotionRank {
                appendPromotions(to: single)
            } else {
                moves.append(Analysis.Move(from: square, to: single))
                if square.rank == startRank,
                   let double = Analysis.Square(file: square.file, rank: square.rank + 2 * direction),
                   self[double] == nil {
                    moves.append(Analysis.Move(from: square, to: double))
                }
            }
        }

        for fileDelta in [-1, 1] {
            guard let target = Analysis.Square(file: square.file + fileDelta, rank: square.rank + direction) else { continue }
            if let occupant = self[target], occupant.color != color {
                if target.rank == promotionRank {
                    appendPromotions(to: target)
                } else {
                    moves.append(Analysis.Move(from: square, to: target))
                }
            } else if target == enPassantTarget, self[target] == nil {
                moves.append(Analysis.Move(from: square, to: target))
            }
        }
        return moves
    }

    private func stepMoves(
        from square: Analysis.Square,
        color: Analysis.Color,
        offsets: [(file: Int, rank: Int)]
    ) -> [Analysis.Move] {
        var moves: [Analysis.Move] = []
        for offset in offsets {
            guard let target = Analysis.Square(file: square.file + offset.file, rank: square.rank + offset.rank) else { continue }
            if let occupant = self[target], occupant.color == color { continue }
            moves.append(Analysis.Move(from: square, to: target))
        }
        return moves
    }

    private func rayMoves(
        from square: Analysis.Square,
        color: Analysis.Color,
        directions: [(file: Int, rank: Int)]
    ) -> [Analysis.Move] {
        var moves: [Analysis.Move] = []
        for direction in directions {
            var file = square.file + direction.file
            var rank = square.rank + direction.rank
            while let target = Analysis.Square(file: file, rank: rank) {
                if let occupant = self[target] {
                    if occupant.color != color {
                        moves.append(Analysis.Move(from: square, to: target))
                    }
                    break
                }
                moves.append(Analysis.Move(from: square, to: target))
                file += direction.file
                rank += direction.rank
            }
        }
        return moves
    }

    private func kingMoves(from square: Analysis.Square, color: Analysis.Color) -> [Analysis.Move] {
        var moves = stepMoves(from: square, color: color, offsets: Analysis.kingOffsets)
        moves.append(contentsOf: castlingMoves(from: square, color: color))
        return moves
    }

    /// Rights say the king and rook have never moved; this still re-verifies
    /// their placement and the path, so a stale persisted right cannot castle.
    private func castlingMoves(from square: Analysis.Square, color: Analysis.Color) -> [Analysis.Move] {
        let homeRank = color == .white ? 0 : 7
        guard square.file == 4, square.rank == homeRank,
              self[square] == Analysis.Piece(color: color, kind: .king),
              !isAttacked(square, by: color.opposite)
        else { return [] }

        var moves: [Analysis.Move] = []
        let rook = Analysis.Piece(color: color, kind: .rook)

        let kingSideRight = color == .white ? Analysis.CastlingRights.whiteKingSide : .blackKingSide
        if castling.contains(kingSideRight),
           self[Analysis.Square(file: 7, rank: homeRank)!] == rook,
           self[Analysis.Square(file: 5, rank: homeRank)!] == nil,
           self[Analysis.Square(file: 6, rank: homeRank)!] == nil,
           !isAttacked(Analysis.Square(file: 5, rank: homeRank)!, by: color.opposite) {
            moves.append(Analysis.Move(from: square, to: Analysis.Square(file: 6, rank: homeRank)!))
        }

        let queenSideRight = color == .white ? Analysis.CastlingRights.whiteQueenSide : .blackQueenSide
        if castling.contains(queenSideRight),
           self[Analysis.Square(file: 0, rank: homeRank)!] == rook,
           self[Analysis.Square(file: 1, rank: homeRank)!] == nil,
           self[Analysis.Square(file: 2, rank: homeRank)!] == nil,
           self[Analysis.Square(file: 3, rank: homeRank)!] == nil,
           !isAttacked(Analysis.Square(file: 3, rank: homeRank)!, by: color.opposite) {
            moves.append(Analysis.Move(from: square, to: Analysis.Square(file: 2, rank: homeRank)!))
        }
        return moves
    }
}
