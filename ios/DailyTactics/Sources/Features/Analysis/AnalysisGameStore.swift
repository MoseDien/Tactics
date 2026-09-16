import Foundation
import Observation

/// Interaction state over `Analysis.Game`: selection, legal-target dots,
/// the promotion queue, and board orientation. The engine stays pure.
@MainActor
@Observable
final class AnalysisGameStore {
    private(set) var game: Analysis.Game
    private(set) var selectedSquare: Analysis.Square?
    private(set) var legalTargets: Set<Analysis.Square> = []
    private(set) var pendingPromotion: (from: Analysis.Square, to: Analysis.Square)?
    var isFlipped = false

    /// A bad seed falls back to the standard opening position.
    init(seedFEN: String) {
        game = (try? Analysis.Game(fen: seedFEN)) ?? Analysis.Game.start()
    }

    var position: Analysis.Position { game.position }
    var status: Analysis.Status { game.status }
    var lastMove: Analysis.Move? { game.lastMove }
    var canUndo: Bool { game.canUndo }
    var hasMoves: Bool { game.hasMoves }

    func select(_ square: Analysis.Square) {
        if pendingPromotion != nil {
            clearSelection()
            pendingPromotion = nil
            return
        }
        if let selected = selectedSquare {
            if square == selected {
                clearSelection()
                return
            }
            if legalTargets.contains(square) {
                if needsPromotion(from: selected, to: square) {
                    pendingPromotion = (from: selected, to: square)
                } else {
                    game.play(Analysis.Move(from: selected, to: square))
                    clearSelection()
                }
                return
            }
        }
        if let piece = position[square], piece.color == position.activeColor {
            selectedSquare = square
            legalTargets = Set(position.legalMoves(from: square).map(\.to))
        } else {
            clearSelection()
        }
    }

    func choosePromotion(_ kind: Analysis.PieceKind) {
        guard let pending = pendingPromotion else { return }
        game.play(Analysis.Move(from: pending.from, to: pending.to, promotion: kind))
        pendingPromotion = nil
        clearSelection()
    }

    func undo() {
        game.undo()
        clearSelection()
    }

    func reset() {
        game.resetToSeed()
        clearSelection()
    }

    func flip() {
        isFlipped.toggle()
    }

    private func clearSelection() {
        selectedSquare = nil
        legalTargets = []
    }

    private func needsPromotion(from: Analysis.Square, to: Analysis.Square) -> Bool {
        guard position[from]?.kind == .pawn else { return false }
        let lastRank = position.activeColor == .white ? 7 : 0
        return to.rank == lastRank
    }
}
