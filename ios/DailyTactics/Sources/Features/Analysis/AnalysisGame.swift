import Foundation

extension Analysis {
    enum Status: Equatable, Sendable {
        case playing
        case check
        case checkmate(winner: Color)
        case stalemate

        static func of(_ position: Position) -> Status {
            let moves = position.legalMoves(for: position.activeColor)
            guard let king = position.kingSquare(of: position.activeColor) else { return .playing }
            let inCheck = position.isAttacked(king, by: position.activeColor.opposite)
            if moves.isEmpty {
                return inCheck ? .checkmate(winner: position.activeColor.opposite) : .stalemate
            }
            return inCheck ? .check : .playing
        }
    }

    /// Snapshot history: undo drops a frame instead of unmaking a move, so
    /// castling rights, EP targets, and clocks can never drift.
    struct Game: Equatable, Sendable {
        let seedFEN: String
        private(set) var positions: [Position]
        private(set) var moves: [Move]

        init(fen: String = Position.startFEN) throws {
            let seed = try Position(fen: fen)
            seedFEN = seed.fen
            positions = [seed]
            moves = []
        }

        static func start() -> Game {
            (try? Game())!
        }

        var position: Position { positions[positions.count - 1] }
        var lastMove: Move? { moves.last }
        var status: Status { Status.of(position) }
        var canUndo: Bool { positions.count > 1 }
        var hasMoves: Bool { !moves.isEmpty }

        mutating func play(_ move: Move) {
            positions.append(position.applying(move))
            moves.append(move)
        }

        mutating func undo() {
            guard canUndo else { return }
            positions.removeLast()
            moves.removeLast()
        }

        mutating func resetToSeed() {
            guard let seed = positions.first else { return }
            positions = [seed]
            moves = []
        }
    }
}
