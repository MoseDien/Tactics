import Foundation
import Observation

enum TacticsFeedbackState: Equatable {
    case idle
    case instruction(message: String, systemImage: String)
    case error(message: String)
    case opponentMoving
    case opponentReply
    case incorrectMove
    case reviewing
    case puzzleComplete
    case trainingComplete
}

enum TacticsMode { case play, reviewBatch }

@MainActor
@Observable
final class TacticsViewModel {
    private var dataset: [Puzzle]
    /// Queries SwiftData at each batch boundary.
    private let dailyPuzzleCount: Int
    private(set) var mode: TacticsMode
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
    private var isAdvancing = false
    /// Remains true after the puzzle is solved, even while the user scrubs
    /// backward through the solution during review.
    private var currentPuzzleFinished = false
    private(set) var userRating: Int
    private(set) var lastRatingDelta: Int?
    private(set) var isBoardFlipped: Bool = false

    /// Per-puzzle outcome for the current round. `nil` = not yet attempted.
    private(set) var results: [PuzzleOutcome?] = []

    init(dataset: [Puzzle] = Puzzle.loadBundled(), progress: PuzzleProgressStore? = nil, ratingStore: UserRatingStore = UserRatingStore(), dailyPuzzleCount: Int = 5, mode: TacticsMode = .play) {
        let source = dataset.isEmpty ? Puzzle.samples : dataset
        let batch = Self.pickRandomBatch(from: source, count: dailyPuzzleCount)
        self.dataset = source
        self.dailyPuzzleCount = dailyPuzzleCount
        self.mode = mode
        self.progress = progress
        self.ratingStore = ratingStore
        userRating = ratingStore.rating
        self.puzzles = batch
        results = Array(repeating: nil, count: batch.count)
        currentIndex = 0
        do {
            session = try PuzzleSession(puzzle: batch[0])
        } catch {
            preconditionFailure("Invalid bundled puzzle: \(error)")
        }
        orientBoardToPlayer()
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
    var headerTitle: String { String(localized: state == .solved ? "tactics.puzzle_complete" : "tactics.your_turn") }
    var headerSubtitle: String {
        String(localized: playerColor == .white ? "tactics.find_best_white" : "tactics.find_best_black")
    }

    var feedbackState: TacticsFeedbackState {
        if errorMessage != nil {
            return .error(message: errorMessage ?? "")
        }
        if currentPuzzleFinished {
            return isLastPuzzle ? .trainingComplete : .puzzleComplete
        }
        if inReview && state != .solved {
            return .reviewing
        }

        switch state {
        case .waitingForMove:
            // No instruction text while simply waiting — the header already
            // says whose move it is. Only the hint surfaces guidance here.
            return hintMove == nil ? .idle : .instruction(message: String(localized: "tactics.hint_instruction"), systemImage: "info.circle")
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
    var isBatchComplete: Bool { isLastPuzzle && currentPuzzleFinished }

    /// The puzzle has been completed at least once. Review navigation must not
    /// revoke this state or disable the Next puzzle action.
    /// Once the current puzzle is finished, navigation is available. At the
    /// end of a batch we deliberately keep it enabled so the user can loop
    /// back through the completed batch for review, even in Play mode.
    var canAdvanceToNextPuzzle: Bool {
        currentPuzzleFinished && (!isLastPuzzle || isBatchComplete)
    }
    var canStartNewBatch: Bool { mode == .reviewBatch && !BatchStore.isWithinDuration }
    var canUpdateRating: Bool { mode == .play }
    var canInteractWithPuzzle: Bool { !inReview && (state == .waitingForMove || state == .incorrectMove) }

    /// The current puzzle's Lichess difficulty rating, if the dataset provides it.
    var currentPuzzleRating: Int? {
        puzzles.indices.contains(currentIndex) ? puzzles[currentIndex].rating : nil
    }

    /// How many times the current puzzle has been played on Lichess.
    var currentPuzzlePlayCount: Int? {
        puzzles.indices.contains(currentIndex) ? puzzles[currentIndex].playCount : nil
    }

    func nextPuzzle() {
        guard !isAdvancing, (mode == .reviewBatch || canAdvanceToNextPuzzle) else { return }
        isAdvancing = true
        // Reaching the end of a Play batch and choosing Next puzzle means the
        // user is reviewing that completed batch. Keep the mode indicator and
        // rating rules aligned with this transition.
        if mode == .play && isBatchComplete {
            mode = .reviewBatch
        }
        let shouldLoopBatch = mode == .reviewBatch || isBatchComplete
        let target = shouldLoopBatch ? (currentIndex + 1) % puzzles.count : currentIndex + 1
        // A brief beat before the next puzzle appears so the transition reads
        // as deliberate rather than an instant snap. Re-entry is blocked until
        // the load completes so repeated taps can't skip puzzles.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            currentIndex = target
            loadPuzzle(at: target)
            isAdvancing = false
        }
    }

    /// Starts a fresh batch only after the user explicitly taps Next batch.
    /// Expiry alone never changes Review mode.
    func startNextBatch() {
        if BatchStore.isWithinDuration {
            // The current batch is still inside its time window. Keep its
            // puzzles and explicitly enter batch review instead of silently
            // doing nothing or creating a replacement batch.
            mode = .reviewBatch
            currentIndex = 0
            loadPuzzle(at: 0)
            return
        }
        mode = .play
        loadNextRound()
    }

    /// Start the next round. This is the only round boundary: in database-backed
    /// (training) mode it queries the store for 5 random unattempted puzzles;
    /// The round cursor always resets to 0.
    func restartBatch() {
        startNextBatch()
    }

    private func loadNextRound() {
        let picked: [Puzzle]
        guard let progress else { return }
        let previousBatchIDs = Set(BatchStore.activePuzzleIDs)
        let candidatePool = progress.fetchUnattemptedRound(count: dailyPuzzleCount, difficulty: DifficultyModeStore.current, userRating: userRating)
            .filter { !previousBatchIDs.contains($0.id) }
        if candidatePool.count >= dailyPuzzleCount {
            picked = Array(candidatePool.prefix(dailyPuzzleCount))
        } else {
            let fallback = progress.allPuzzles().filter { !previousBatchIDs.contains($0.id) }
            picked = Array(fallback.shuffled().prefix(min(dailyPuzzleCount, fallback.count)))
        }
        guard !picked.isEmpty else { return }
        puzzles = picked
        BatchStore.begin(with: picked)
        results = Array(repeating: nil, count: picked.count)
        currentIndex = 0
        loadPuzzle(at: 0)
    }

    // MARK: - Review stepping

    /// `<`/`>` are review-only: available once the puzzle is solved (or while
    /// scrubbing the line afterwards). Disabled during active play.
    var inReview: Bool { session.state == .solved || session.isReviewing }
    var hintEnabled: Bool {
        !inReview && (session.state == .waitingForMove || session.state == .incorrectMove)
    }
    var isReviewing: Bool { session.isReviewing }
    var currentMoveNumber: Int { session.currentMoveNumber }
    var totalUserMoves: Int { session.totalUserMoves }


    /// Revealing a hint counts as giving up on this puzzle: it is scored
    /// immediately as a loss (rating decreases) and marked attempted, so a
    /// later clean solve can't recover the points.
    func requestHint() {
        guard hintEnabled, let expected = session.expectedMove else { return }
        hadMistake = true
        hintMove = expected
        applyHintPenalty()
    }

    /// Charge the rating for using a hint, once per puzzle. Idempotent so
    /// repeated taps don't stack penalties.
    private func applyHintPenalty() {
        guard !ratingAppliedForPuzzle else { return }
        ratingAppliedForPuzzle = true
        recordOutcome(.wrong, for: currentIndex)
        applySolveRating(solved: false)
        progress?.markAttempted(puzzles[currentIndex].id)
    }

    // MARK: - Session actions

    func start() {
        guard state == .opponentMoving, session.currentMoveIndex == 0 else { return }
        Task { await playOpponentMove() }
    }

    func select(_ square: Square) {
        guard canInteractWithPuzzle else { return }
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
            currentPuzzleFinished = false
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
            recordOutcome(.wrong, for: currentIndex)
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
        if session.state == .solved && mode == .play {
            markCurrentSolved()
        }
    }

    private func markCurrentSolved() {
        currentPuzzleFinished = true
        // Completion is recorded once regardless of the rating outcome: a hint
        // may have already adjusted the rating before the line is finished.
        progress?.markCompleted(puzzles[currentIndex].id)
        guard !ratingAppliedForPuzzle else { return }
        ratingAppliedForPuzzle = true
        recordOutcome(.correct, for: currentIndex)
        if isLastPuzzle {
            progress?.recordRound(puzzles: puzzles, outcomes: results)
        }
        guard canUpdateRating, firstAttemptWasCorrect else { return }
        let cleanSolve = !hadMistake && hintMove == nil
        applySolveRating(solved: cleanSolve)
    }

    /// Applies an Elo-style rating change for the current puzzle and persists it.
    private func applySolveRating(solved: Bool) {
        guard canUpdateRating else { return }
        let puzzleRating = puzzles[currentIndex].rating ?? userRating
        let delta = ratingCalculator.change(
            userRating: userRating,
            puzzleRating: puzzleRating,
            solved: solved
        )
        userRating = ratingStore.apply(delta: delta)
        lastRatingDelta = delta
    }

    private func recordFailure() {
        guard let progress else { return }
        progress.markFailed(puzzles[currentIndex].id)
    }

    /// Mark a round outcome for the puzzle at `index`. Idempotent: the first
    /// recorded result (e.g. a wrong move) wins, so a later clean solve can't
    /// overwrite an earlier mistake.
    private func recordOutcome(_ outcome: PuzzleOutcome, for index: Int) {
        guard results.indices.contains(index), results[index] == nil else { return }
        results[index] = outcome
    }
}
