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
    private(set) var animatedArrival: [Analysis.Square: Analysis.Square] = [:]
    private(set) var moveRevision = 0
    private(set) var boardGeneration = 0
    private(set) var isUndoAnimation = false
    /// The machine's setup move. It plays itself half a second after load —
    /// and again whenever the board rewinds to the raw seed or resets — so
    /// the solver always starts (again) from the setup position.
    private let openingMove: Analysis.Move?
    /// The pause before the machine's setup move (re)plays itself; injectable
    /// for tests.
    private let openingReplayDelay: Duration
    private var replayTask: Task<Void, Never>?

    /// A bad seed falls back to the standard opening position. The board opens
    /// on the raw seed, oriented like the training board it was launched from;
    /// the setup move follows shortly.
    init(
        seedFEN: String,
        openingMove: Analysis.Move? = nil,
        startsFlipped: Bool = false,
        openingReplayDelay: Duration = .milliseconds(500)
    ) {
        game = (try? Analysis.Game(fen: seedFEN)) ?? Analysis.Game.start()
        self.openingMove = openingMove
        self.openingReplayDelay = openingReplayDelay
        isFlipped = startsFlipped
        scheduleOpeningReplay()
    }

    var position: Analysis.Position { game.position }
    var status: Analysis.Status { game.status }
    var lastMove: Analysis.Move? { game.lastMove }
    var moveList: [Analysis.MoveDisplay] { game.moveList }

    /// The side the solver holds on a seeded board: the machine opens from
    /// the raw seed, so this is the seed's side-to-move flipped. Nil on a
    /// free board without an opener.
    var heldColor: Analysis.Color? {
        guard openingMove != nil, let machineColor = game.positions.first?.activeColor else { return nil }
        return machineColor.opposite
    }
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
                    play(Analysis.Move(from: selected, to: square))
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
        play(Analysis.Move(from: pending.from, to: pending.to, promotion: kind))
        pendingPromotion = nil
        clearSelection()
    }

    func undo() {
        guard let move = game.lastMove else { return }
        game.undo()
        animatedArrival = arrivals(for: move, reversing: true)
        isUndoAnimation = true
        moveRevision += 1
        clearSelection()
        scheduleOpeningReplay()
    }

    func reset() {
        replayTask?.cancel()
        game.resetToSeed()
        animatedArrival = [:]
        isUndoAnimation = false
        boardGeneration += 1
        clearSelection()
        scheduleOpeningReplay()
    }

    func flip() {
        isFlipped.toggle()
    }

    private func clearSelection() {
        selectedSquare = nil
        legalTargets = []
    }

    /// Sitting on the raw seed — at load, after rewinding to the bottom, or
    /// after a reset: after a short pause the machine's setup move plays
    /// itself, handing the solver their starting point. A user move made
    /// during the pause wins and cancels the replay.
    private func scheduleOpeningReplay() {
        guard openingMove != nil, !game.hasMoves else { return }
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: openingReplayDelay)
            guard !Task.isCancelled, self.game.moves.isEmpty, let openingMove = self.openingMove else { return }
            self.play(openingMove)
        }
    }

    private func needsPromotion(from: Analysis.Square, to: Analysis.Square) -> Bool {
        guard position[from]?.kind == .pawn else { return false }
        let lastRank = position.activeColor == .white ? 7 : 0
        return to.rank == lastRank
    }

    private func play(_ move: Analysis.Move) {
        animatedArrival = arrivals(for: move, reversing: false)
        isUndoAnimation = false
        game.play(move)
        moveRevision += 1
    }

    private func arrivals(for move: Analysis.Move, reversing: Bool) -> [Analysis.Square: Analysis.Square] {
        var arrivals = reversing ? [move.from: move.to] : [move.to: move.from]
        guard position[move.from]?.kind == .king, abs(move.to.file - move.from.file) == 2 else {
            return arrivals
        }
        let rookFromFile = move.to.file > move.from.file ? 7 : 0
        let rookToFile = move.to.file > move.from.file ? 5 : 3
        guard let rookFrom = Analysis.Square(file: rookFromFile, rank: move.from.rank),
              let rookTo = Analysis.Square(file: rookToFile, rank: move.from.rank)
        else { return arrivals }
        if reversing {
            arrivals[rookFrom] = rookTo
        } else {
            arrivals[rookTo] = rookFrom
        }
        return arrivals
    }
}
