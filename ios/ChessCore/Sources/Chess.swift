import Foundation

public enum PieceColor: String, Codable, Sendable {
    case white
    case black

    public var opponent: Self { self == .white ? .black : .white }
}

public enum PieceKind: String, Codable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}

public struct Piece: Equatable, Sendable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    public var assetName: String {
        switch (color, kind) {
        case (.white, .king): "wK"
        case (.white, .queen): "wQ"
        case (.white, .rook): "wR"
        case (.white, .bishop): "wB"
        case (.white, .knight): "wN"
        case (.white, .pawn): "wP"
        case (.black, .king): "bK"
        case (.black, .queen): "bQ"
        case (.black, .rook): "bR"
        case (.black, .bishop): "bB"
        case (.black, .knight): "bN"
        case (.black, .pawn): "bP"
        }
    }
}

public struct Square: Hashable, Sendable {
    public let file: Int
    public let rank: Int

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    public init?(notation: String) {
        let characters = Array(notation.lowercased())
        guard characters.count == 2,
              let fileValue = characters[0].asciiValue,
              let rank = Int(String(characters[1])),
              (97...104).contains(fileValue),
              (1...8).contains(rank)
        else { return nil }
        // The guard bounds both values to the board, so this cannot be nil.
        self.init(file: Int(fileValue - 97), rank: rank - 1)!
    }

    public var notation: String {
        "\(Character(UnicodeScalar(UInt8(file + 97))))\(rank + 1)"
    }
}

public struct ChessMove: Equatable, Sendable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public init?(uci: String) {
        guard uci.count == 4 || uci.count == 5 else { return nil }
        let characters = Array(uci.lowercased())
        guard let from = Square(notation: String(characters[0...1])),
              let to = Square(notation: String(characters[2...3]))
        else { return nil }

        let promotion: PieceKind?
        if characters.count == 5 {
            switch characters[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        } else {
            promotion = nil
        }

        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        let suffix: String
        switch promotion {
        case .queen: suffix = "q"
        case .rook: suffix = "r"
        case .bishop: suffix = "b"
        case .knight: suffix = "n"
        default: suffix = ""
        }
        return from.notation + to.notation + suffix
    }
}

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

    private func kingSquare(of color: PieceColor, in pieces: [Square: Piece]) -> Square? {
        pieces.first { _, piece in piece.color == color && piece.kind == .king }?.key
    }

    /// Whether any piece of `attacker`'s color attacks `square` in the classic
    /// sense (capture moves, ignoring en-passant-only oddities).
    private static func isAttacked(
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

    /// `apply` minus the bookkeeping `isLegal` doesn't need. Kept separate so
    /// the legality probe cannot observe intermediate rights/turn updates.
    private mutating func applyUncheckedForLegality(_ move: ChessMove) -> Bool {
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


    private static func shapeIsLegal(
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
