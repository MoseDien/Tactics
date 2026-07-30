import Foundation
import Observation

enum TacticsFeedbackState: Equatable {
    case instruction(message: String, systemImage: String)
    case error(message: String)
    case opponentMoving
    case opponentReply
    case incorrectMove
    case reviewing
    case puzzleComplete
    case trainingComplete
}

@MainActor
@Observable
final class TacticsViewModel {
    private var dataset: [Puzzle]
    private let dailyPuzzleCount: Int
    private(set) var puzzles: [Puzzle]
    private(set) var currentIndex: Int
    private(set) var session: PuzzleSession
    private(set) var selectedSquare: Square?
    private(set) var attemptedMove: ChessMove?
    private(set) var hintMove: ChessMove?
    private(set) var errorMessage: String?
    private var progress: PuzzleProgressStore?
    private let ratingStore: UserRatingStore
    private let ratingCalculator = PuzzleRatingCalculator()
    private var hadMistake = false
    private var ratingAppliedForPuzzle = false
    private var firstAttemptWasCorrect = false
    private(set) var userRating: Int
    private(set) var lastRatingDelta: Int?
    private(set) var isBoardFlipped: Bool = false
    private(set) var levelTransition: RatingLevel?

    init(dataset: [Puzzle] = Puzzle.loadBundled(), progress: PuzzleProgressStore? = nil, ratingStore: UserRatingStore = UserRatingStore(), dailyPuzzleCount: Int = 5, batchSize: Int? = nil) {
        let source = dataset.isEmpty ? Puzzle.samples : dataset
        let requestedCount = batchSize ?? dailyPuzzleCount
        let batch = Self.pickRandomBatch(from: source, count: requestedCount)
        self.dataset = source
        self.dailyPuzzleCount = requestedCount
        self.progress = progress
        self.ratingStore = ratingStore
        userRating = ratingStore.rating
        self.puzzles = batch
        currentIndex = 0
        do {
            session = try PuzzleSession(puzzle: batch[0])
        } catch {
            preconditionFailure("Invalid bundled puzzle: \(error)")
        }
        orientBoardToPlayer()
    }

    func acknowledgeLevelTransition() {
        levelTransition = nil
    }

    func attachProgress(_ store: PuzzleProgressStore) {
        progress = store
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
    var lastMove: ChessMove? { session.lastMove }

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
    var headerTitle: String { state == .solved ? "Puzzle complete!" : "Your turn" }
    var headerSubtitle: String {
        "Find the best move for \(playerColor == .white ? "white" : "black")."
    }

    var feedbackState: TacticsFeedbackState {
        if errorMessage != nil {
            return .error(message: errorMessage ?? "")
        }
        if inReview && state != .solved {
            return .reviewing
        }

        switch state {
        case .waitingForMove:
            return .instruction(
                message: hintMove == nil ? "Find the winning move" : "Move the highlighted piece to the marked square",
                systemImage: hintMove == nil ? "scope" : "lightbulb.fill"
            )
        case .opponentMoving:
            return isReviewing ? .opponentReply : .opponentMoving
        case .incorrectMove:
            return .incorrectMove
        case .solved:
            return isBatchComplete ? .trainingComplete : .puzzleComplete
        }
    }

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

    /// Reshuffle a fresh random batch from the current dataset.
    func restartBatch() {
        reshuffleBatch()
    }

    /// Replace the dataset (e.g. after a rating-level transition imports a new
    /// tier) and start a fresh batch from it. A no-op when the new dataset is
    /// empty, so a failed import never leaves the user without puzzles.
    func reload(dataset: [Puzzle]) {
        guard !dataset.isEmpty else { return }
        self.dataset = dataset
        reshuffleBatch()
    }

    private func reshuffleBatch() {
        let available = dataset.filter { !(progress?.hasAttempted($0.id) ?? false) }
        let source = available.count >= dailyPuzzleCount ? available : dataset
        puzzles = Self.pickRandomBatch(from: source, count: dailyPuzzleCount)
        currentIndex = 0
        loadPuzzle(at: 0)
    }

    // MARK: - Review stepping

    /// `<`/`>` are review-only: available once the puzzle is solved (or while
    /// scrubbing the line afterwards). Disabled during active play.
    var inReview: Bool { session.state == .solved || session.isReviewing }
    var canStepForward: Bool { inReview && session.canStepForward }
    var canStepBack: Bool { inReview && session.canStepBack }
    var hintEnabled: Bool {
        !inReview && (session.state == .waitingForMove || session.state == .incorrectMove)
    }
    var isReviewing: Bool { session.isReviewing }
    var currentMoveNumber: Int { session.currentMoveNumber }
    var totalUserMoves: Int { session.totalUserMoves }

    func stepForward() {
        guard canStepForward else { return }
        do {
            try session.stepForward()
            selectedSquare = nil
            attemptedMove = nil
            hintMove = nil
        } catch {
            errorMessage = "The next move could not be shown."
        }
    }

    /// Highlight the piece and its destination for the current expected move.
    /// Decoupled from `>` — it never reveals the line or unlocks the stepper.
    func requestHint() {
        guard hintEnabled, let expected = session.expectedMove else { return }
        hadMistake = true
        hintMove = expected
    }

    func stepBack() {
        guard canStepBack else { return }
        do {
            try session.stepBack()
            selectedSquare = nil
            attemptedMove = nil
            hintMove = nil
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
        guard !inReview,
              state == .waitingForMove || state == .incorrectMove else { return }
        attemptedMove = nil
        hintMove = nil

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

    private static func pickRandomBatch(from dataset: [Puzzle], count: Int = 5) -> [Puzzle] {
        Array(dataset.shuffled().prefix(min(count, dataset.count)))
    }

    private func loadPuzzle(at index: Int) {
        do {
            session = try PuzzleSession(puzzle: puzzles[index])
            selectedSquare = nil
            hintMove = nil
            attemptedMove = nil
            errorMessage = nil
            hadMistake = false
            firstAttemptWasCorrect = false
            ratingAppliedForPuzzle = false
            lastRatingDelta = nil
            orientBoardToPlayer()
            Task { await playOpponentMove() }
        } catch {
            errorMessage = "The puzzle could not be loaded."
        }
    }

    private func attemptMove(from origin: Square, to target: Square) {
        hintMove = nil
        var move = ChessMove(from: origin, to: target)
        if session.moveNeedsPromotion(move) {
            move = ChessMove(from: origin, to: target, promotion: .queen)
        }
        // The expected move is trusted-legal (from the puzzle line), so accept
        // it even for special moves (castling, en passant) the basic legality
        // check does not model. Any other move must be basically legal.
        let isExpected = move == session.expectedMove
        guard isExpected || session.isLegalUserMove(move) else { return }

        let puzzleID = puzzles[currentIndex].id
        let isFirstAttempt = !(progress?.hasAttempted(puzzleID) ?? false)
        if isFirstAttempt {
            firstAttemptWasCorrect = isExpected
            progress?.markAttempted(puzzleID)
        }

        selectedSquare = nil
        do {
            try session.submitUserMove(move)
        } catch {
            errorMessage = "The move could not be applied."
            return
        }

        switch state {
        case .incorrectMove:
            // Wrong move: record it as a failure, then let the user retry.
            recordFailure()
            hadMistake = true
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
        guard !ratingAppliedForPuzzle else { return }
        ratingAppliedForPuzzle = true
        guard firstAttemptWasCorrect else {
            progress?.markCompleted(puzzles[currentIndex].id)
            return
        }
        let puzzleRating = puzzles[currentIndex].rating ?? userRating
        let cleanSolve = !hadMistake && hintMove == nil
        let delta = ratingCalculator.change(
            userRating: userRating,
            puzzleRating: puzzleRating,
            solved: cleanSolve
        )
        userRating = ratingStore.apply(delta: delta)
        let newLevel = RatingLevel(rating: userRating)
        if newLevel != ratingStore.level {
            levelTransition = newLevel
            ratingStore.set(rating: userRating)
        }
        lastRatingDelta = delta
        guard let progress else { return }
        progress.markCompleted(puzzles[currentIndex].id)
    }

    private func recordFailure() {
        guard let progress else { return }
        progress.markFailed(puzzles[currentIndex].id)
    }
}
