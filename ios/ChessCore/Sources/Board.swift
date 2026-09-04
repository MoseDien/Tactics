import Foundation

public struct Board: Equatable, Sendable {
    public enum FENError: Error, Equatable {
        case missingFields
        case invalidRankCount
        case invalidRank(String)
        case invalidPiece(Character)
        case invalidSideToMove(String)
    }

    /// Castling availability parsed from the FEN's third field ("KQkq" style).
    /// Empty when the FEN omits or blanks the field.
    public struct CastlingRights: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let whiteKingSide = CastlingRights(rawValue: 1 << 0)
        public static let whiteQueenSide = CastlingRights(rawValue: 1 << 1)
        public static let blackKingSide = CastlingRights(rawValue: 1 << 2)
        public static let blackQueenSide = CastlingRights(rawValue: 1 << 3)
    }

    public private(set) var pieces: [Square: Piece]
    public private(set) var sideToMove: PieceColor
    /// FEN fields 3–4. Kept for validation and special-move handling; the
    /// halfmove clock and fullmove number (fields 5–6) are not needed for
    /// tactics lines and are not stored.
    public private(set) var castlingRights: CastlingRights
    /// The square where en passant capture is possible, if any.
    public private(set) var enPassantTarget: Square?
    /// Set by `apply` when a move leaves the mover's king attacked. The board
    /// is a passive record of the position; check detection lives here so
    /// `isLegal` can reject self-checks and `apply` stays unchecked.
    public private(set) var sideToMoveInCheck: Bool = false

    public init(fen: String) throws {
        let fields = fen.split(separator: " ")
        guard fields.count >= 2 else { throw FENError.missingFields }

        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { throw FENError.invalidRankCount }

        var parsedPieces: [Square: Piece] = [:]
        for (rankIndex, encodedRank) in ranks.enumerated() {
            var file = 0
            var previousWasDigit = false
            for character in encodedRank {
                // Only a single ASCII digit 1–8 is a rank skip. Non-ASCII
                // digits ("٣") and multi-digit runs ("44") are rejected rather
                // than summed or silently accepted.
                if let emptyCount = character.wholeNumberValue, character.isASCII {
                    guard (1...8).contains(emptyCount), !previousWasDigit else {
                        throw FENError.invalidRank(String(encodedRank))
                    }
                    file += emptyCount
                    previousWasDigit = true
                } else {
                    guard file < 8, let piece = Self.piece(for: character) else {
                        throw FENError.invalidPiece(character)
                    }
                    parsedPieces[Square(file: file, rank: 7 - rankIndex)!] = piece
                    file += 1
                    previousWasDigit = false
                }
            }
            guard file == 8 else { throw FENError.invalidRank(String(encodedRank)) }
        }

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: throw FENError.invalidSideToMove(String(fields[1]))
        }
        castlingRights = Self.castlingRights(fields.count > 2 ? String(fields[2]) : "")
        enPassantTarget = fields.count > 3 ? Square(notation: String(fields[3])) : nil
        pieces = parsedPieces
        sideToMoveInCheck = Self.isAttacked(
            kingSquare(of: sideToMove, in: parsedPieces),
            by: sideToMove.opponent,
            in: parsedPieces,
            enPassantTarget: nil
        )
    }

    private static func castlingRights(_ field: String) -> CastlingRights {
        var rights: CastlingRights = []
        if field.contains("K") { rights.insert(.whiteKingSide) }
        if field.contains("Q") { rights.insert(.whiteQueenSide) }
        if field.contains("k") { rights.insert(.blackKingSide) }
        if field.contains("q") { rights.insert(.blackQueenSide) }
        return rights
    }

    public mutating func apply(_ move: ChessMove) -> Bool {
        guard let movingPiece = pieces.removeValue(forKey: move.from) else { return false }
        let targetWasEmpty = pieces[move.to] == nil
        let resultingKind = move.promotion ?? movingPiece.kind
        pieces[move.to] = Piece(color: movingPiece.color, kind: resultingKind)

        // Castling: a king advancing two files also relocates the corner rook.
        // The rook must actually be there; otherwise the king simply moved
        // (a data bug, not a position we should corrupt with a phantom rook).
        if movingPiece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6, let rook = pieces.removeValue(forKey: Square(file: 7, rank: rank)!) {
                pieces[Square(file: 5, rank: rank)!] = rook
            } else if move.to.file == 2, let rook = pieces.removeValue(forKey: Square(file: 0, rank: rank)!) {
                pieces[Square(file: 3, rank: rank)!] = rook
            }
        }

        // En passant: a pawn moving diagonally onto an empty square captures
        // the enemy pawn beside its origin. Only the square an en-passant
        // capture can actually remove — an enemy pawn on it — is cleared.
        if movingPiece.kind == .pawn,
           move.from.file != move.to.file,
           targetWasEmpty {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)!
            if pieces[capturedSquare]?.color == movingPiece.color.opponent {
                pieces.removeValue(forKey: capturedSquare)
            }
        }

        // Toggle the recorded turn and update the special-move context so the
        // next `isLegal` call answers for the side about to move.
        sideToMove = sideToMove.opponent
        enPassantTarget = (movingPiece.kind == .pawn && abs(move.to.rank - move.from.rank) == 2)
            ? Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)!
            : nil
        if !castlingRights.isEmpty {
            if movingPiece.kind == .king {
                let whiteRights: CastlingRights = [.whiteKingSide, .whiteQueenSide]
                let blackRights: CastlingRights = [.blackKingSide, .blackQueenSide]
                castlingRights.subtract(movingPiece.color == .white ? whiteRights : blackRights)
            }
            if movingPiece.kind == .rook {
                let backRank = movingPiece.color == .white ? 0 : 7
                if move.from == Square(file: 0, rank: backRank)! {
                    castlingRights.subtract(movingPiece.color == .white ? .whiteQueenSide : .blackQueenSide)
                } else if move.from == Square(file: 7, rank: backRank)! {
                    castlingRights.subtract(movingPiece.color == .white ? .whiteKingSide : .blackKingSide)
                }
            }
        }
        sideToMoveInCheck = Self.isAttacked(
            kingSquare(of: sideToMove, in: pieces),
            by: sideToMove.opponent,
            in: pieces,
            enPassantTarget: enPassantTarget
        )
        return true
    }

    /// `apply` minus the bookkeeping `isLegal` doesn't need. Kept separate so
    /// the legality probe cannot observe intermediate rights/turn updates.
    mutating func applyUncheckedForLegality(_ move: ChessMove) -> Bool {
        guard let movingPiece = pieces.removeValue(forKey: move.from) else { return false }
        let targetWasEmpty = pieces[move.to] == nil
        pieces[move.to] = Piece(color: movingPiece.color, kind: move.promotion ?? movingPiece.kind)

        if movingPiece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6, let rook = pieces.removeValue(forKey: Square(file: 7, rank: rank)!) {
                pieces[Square(file: 5, rank: rank)!] = rook
            } else if move.to.file == 2, let rook = pieces.removeValue(forKey: Square(file: 0, rank: rank)!) {
                pieces[Square(file: 3, rank: rank)!] = rook
            }
        }

        if movingPiece.kind == .pawn, move.from.file != move.to.file, targetWasEmpty {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)!
            if pieces[capturedSquare]?.color == movingPiece.color.opponent {
                pieces.removeValue(forKey: capturedSquare)
            }
        }
        return true
    }


    func kingSquare(of color: PieceColor, in pieces: [Square: Piece]) -> Square? {
        pieces.first { _, piece in piece.color == color && piece.kind == .king }?.key
    }

    /// Whether any piece of `attacker`'s color attacks `square` in the classic
    /// sense (capture moves, ignoring en-passant-only oddities).
    static func isAttacked(
        _ square: Square?,
        by attacker: PieceColor,
        in pieces: [Square: Piece],
        enPassantTarget: Square?
    ) -> Bool {
        guard let square else { return false }

        for (origin, piece) in pieces where piece.color == attacker {
            switch piece.kind {
            case .pawn:
                let direction = attacker == .white ? 1 : -1
                if abs(square.file - origin.file) == 1, square.rank - origin.rank == direction { return true }
            case .knight:
                if (abs(square.file - origin.file), abs(square.rank - origin.rank)) == (1, 2)
                    || (abs(square.file - origin.file), abs(square.rank - origin.rank)) == (2, 1) { return true }
            case .king:
                if max(abs(square.file - origin.file), abs(square.rank - origin.rank)) == 1 { return true }
            case .bishop, .rook, .queen:
                if shapeIsLegal(piece, from: origin, to: square, in: pieces) {
                    // A king adjacent to the checked king still attacks it even
                    // though the reverse would be illegal; shapeIsLegal already
                    // covers that, so the shape test alone is sufficient here.
                    return true
                }
            }
        }
        return false
    }

    private static func piece(for character: Character) -> Piece? {
        let color: PieceColor = character.isUppercase ? .white : .black
        let kind: PieceKind
        switch character.lowercased() {
        case "k": kind = .king
        case "q": kind = .queen
        case "r": kind = .rook
        case "b": kind = .bishop
        case "n": kind = .knight
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(color: color, kind: kind)
    }
}
