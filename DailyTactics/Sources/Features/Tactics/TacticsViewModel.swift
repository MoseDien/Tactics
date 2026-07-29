import Foundation
import Observation

@MainActor
@Observable
final class TacticsViewModel {
    private let dataset: [Puzzle]
    private(set) var puzzles: [Puzzle]
    private(set) var currentIndex: Int
    private(set) var session: PuzzleSession
    private(set) var selectedSquare: Square?
    private(set) var attemptedMove: ChessMove?
    private(set) var errorMessage: String?
    private var progress: PuzzleProgressStore?
    private(set) var completedCount: Int = 0
    private(set) var isBoardFlipped: Bool = false

    init(dataset: [Puzzle] = Puzzle.loadBundled(), progress: PuzzleProgressStore? = nil) {
        let source = dataset.isEmpty ? Puzzle.samples : dataset
        let batch = Self.pickRandomBatch(from: source)
        self.dataset = source
        self.progress = progress
        self.puzzles = batch
        currentIndex = 0
        do {
            session = try PuzzleSession(puzzle: batch[0])
        } catch {
            preconditionFailure("Invalid bundled puzzle: \(error)")
        }
        orientBoardToPlayer()
        completedCount = progress?.completedCount() ?? 0
    }

    func attachProgress(_ store: PuzzleProgressStore) {
        progress = store
        completedCount = store.completedCount()
    }

    /// Flip the board between the two playing perspectives.
    func toggleBoardFlip() {
        isBoardFlipped.toggle()
    }

    /// Orient the board so the player's own pieces are at the bottom. Called on
    /// every puzzle load so the user always starts from their perspective.
    private func orientBoardToPlayer() {
        isBoardFlipped = session.userColor == .black
    }

    // MARK: - Board state

    var position: [Square: Piece] { session.board.pieces }

    /// Position shown on the board. While a wrong move is being demonstrated, the
    /// moved piece is shown on its target square; clearing `attemptedMove` snaps it back.
    var displayedPosition: [Square: Piece] {
        guard let attempt = attemptedMove, let piece = position[attempt.from] else {
            return position
        }
        var preview = position
        preview.removeValue(forKey: attempt.from)
        preview[attempt.to] = piece
        return preview
    }

    var state: PuzzleSessionState { session.state }
    var playerColor: PieceColor { session.userColor }

    // MARK: - Batch navigation

    var puzzleCount: Int { puzzles.count }
    var puzzleNumber: Int { currentIndex + 1 }
    var isLastPuzzle: Bool { currentIndex >= puzzles.count - 1 }
    var isBatchComplete: Bool { isLastPuzzle && session.state == .solved }

    func nextPuzzle() {
        guard currentIndex < puzzles.count - 1 else { return }
        currentIndex += 1
        loadPuzzle(at: currentIndex)
    }

    /// Reshuffle a fresh random batch of three from the full dataset.
    func restartBatch() {
        puzzles = Self.pickRandomBatch(from: dataset)
        currentIndex = 0
        loadPuzzle(at: 0)
    }

    // MARK: - Review stepping

    var canStepForward: Bool { session.canStepForward }
    var canStepBack: Bool { session.canStepBack }
    var isReviewing: Bool { session.isReviewing }
    var currentMoveNumber: Int { session.currentMoveNumber }
    var totalUserMoves: Int { session.totalUserMoves }

    func stepForward() {
        do {
            try session.stepForward()
            selectedSquare = nil
        } catch {
            errorMessage = "The next move could not be shown."
        }
    }

    func stepBack() {
        do {
            try session.stepBack()
            selectedSquare = nil
        } catch {
            errorMessage = "The previous move could not be shown."
        }
    }

    // MARK: - Session actions

    func start() {
        guard state == .opponentMoving, session.currentMoveIndex == 0 else { return }
        Task { await playOpponentMove() }
    }

    func select(_ square: Square) {
        guard state == .waitingForMove || state == .incorrectMove else { return }
        attemptedMove = nil

        if state == .incorrectMove {
            session.resumeAfterIncorrectMove()
        }

        if let selectedSquare {
            if selectedSquare == square {
                self.selectedSquare = nil
            } else if position[square]?.color == session.userColor {
                self.selectedSquare = square
            } else {
                attemptMove(from: selectedSquare, to: square)
            }
        } else if position[square]?.color == session.userColor {
            selectedSquare = square
        }
    }

    func restart() {
        loadPuzzle(at: currentIndex)
    }

    private static func pickRandomBatch(from dataset: [Puzzle]) -> [Puzzle] {
        Array(dataset.shuffled().prefix(min(3, dataset.count)))
    }

    private func loadPuzzle(at index: Int) {
        do {
            session = try PuzzleSession(puzzle: puzzles[index])
            selectedSquare = nil
            attemptedMove = nil
            errorMessage = nil
            orientBoardToPlayer()
            Task { await playOpponentMove() }
        } catch {
            errorMessage = "The puzzle could not be loaded."
        }
    }

    private func attemptMove(from origin: Square, to target: Square) {
        var move = ChessMove(from: origin, to: target)
        if session.moveNeedsPromotion(move) {
            move = ChessMove(from: origin, to: target, promotion: .queen)
        }
        // The expected move is trusted-legal (from the puzzle line), so accept
        // it even for special moves (castling, en passant) the basic legality
        // check does not model. Any other move must be basically legal.
        let isExpected = move == session.expectedMove
        guard isExpected || session.isLegalUserMove(move) else { return }

        selectedSquare = nil
        do {
            try session.submitUserMove(move)
        } catch {
            errorMessage = "The move could not be applied."
            return
        }

        switch state {
        case .incorrectMove:
            // Legal but wrong: briefly show the piece on the target, then snap back.
            attemptedMove = move
            let attempted = move
            Task {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, attemptedMove == attempted else { return }
                attemptedMove = nil
            }
        case .solved:
            markCurrentSolved()
        case .opponentMoving:
            Task { await playOpponentMove() }
        default:
            break
        }
    }

    private func playOpponentMove() async {
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do {
            try session.applyOpponentMove()
        } catch {
            errorMessage = "The reply could not be applied."
            return
        }
        if session.state == .solved {
            markCurrentSolved()
        }
    }

    private func markCurrentSolved() {
        guard let progress else { return }
        progress.markCompleted(puzzles[currentIndex].id)
        completedCount = progress.completedCount()
    }
}
