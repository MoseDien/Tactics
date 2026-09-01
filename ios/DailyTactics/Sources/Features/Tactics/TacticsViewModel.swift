import Foundation
import ChessCore
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
    /// Pending promotion: set when a pawn move reaches the last rank, cleared
    /// once the player picks a piece (or the move is cancelled by re-selection).
    private(set) var pendingPromotion: (from: Square, to: Square)?
    private var progress: PuzzleProgressStore?
    private let ratingStore: UserRatingStore
    private let ratingCalculator = PuzzleRatingCalculator()
    private var hadMistake = false
    private var ratingAppliedForPuzzle = false
    private var firstAttemptWasCorrect = false
    private var isAdvancing = false
    /// Whether this batch has already been written to `RoundHistory`. The
    /// round is recorded exactly once per batch — re-solving puzzles in review
    /// (or solving the last one after a hint) must not insert or skip a row.
    private var roundRecorded = false
    /// Remains true after the puzzle is solved, even while the user scrubs
    /// backward through the solution during review.
    private var currentPuzzleFinished = false
    private(set) var userRating: Int
    private(set) var lastRatingDelta: Int?
    private(set) var isBoardFlipped: Bool = false
    /// Message surfaced when the user taps "Next batch" inside the cooldown
    /// window. Cleared on the next puzzle load.
    private(set) var batchCooldownMessage: String?

    /// Per-puzzle outcome for the current round. `nil` = not yet attempted.
    private(set) var results: [PuzzleOutcome?] = []

    init(dataset: [Puzzle], progress: PuzzleProgressStore? = nil, ratingStore: UserRatingStore = UserRatingStore(), dailyPuzzleCount: Int = 5, mode: TacticsMode = .play) {
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
        roundRecorded = false
        currentIndex = 0
        do {
            session = try PuzzleSession(puzzle: batch[0])
        } catch {
            // A puzzle that cannot build a session is unusable, but crashing
            // the app over one data row is worse: fall back to the samples,
            // which are hand-verified.
            session = (try? PuzzleSession(puzzle: Puzzle.samples[0])) ?? PuzzleSession.empty()
            errorMessage = String(localized: "tactics.error_load")
        }
        orientBoardToPlayer()
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

    /// Test hook: the live session value.
    func sessionForTest() -> PuzzleSession { session }

    /// Test hook: whether the promotion picker is up.
    func pendingPromotionForTest() -> (from: Square, to: Square)? { pendingPromotion }
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
    /// Whether the batch window has expired — a new batch can start right now.
    /// Purely time-based; `canStartNewBatch` additionally requires review mode.
    var isNewBatchAvailable: Bool { !BatchStore.isWithinDuration }
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
            // The current batch is still inside its time window: surface why
            // nothing new is coming and stay on the batch being reviewed.
            batchCooldownMessage = String(localized: "tactics.batch_cooldown")
            return
        }
        batchCooldownMessage = nil
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
        roundRecorded = false
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
                pendingPromotion = nil
            } else if position[square]?.color == session.userColor {
                self.selectedSquare = square
                pendingPromotion = nil
            } else {
                attemptMove(from: selectedSquare, to: square)
            }
        } else if position[square]?.color == session.userColor {
            selectedSquare = square
        }
    }

    /// The player picked a promotion piece for the pending pawn move.
    func choosePromotion(_ kind: PieceKind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        selectedSquare = nil
        attemptMove(from: pending.from, to: pending.to, promotion: kind)
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
            batchCooldownMessage = nil
            pendingPromotion = nil
            hadMistake = false
            firstAttemptWasCorrect = false
            ratingAppliedForPuzzle = false
            lastRatingDelta = nil
            orientBoardToPlayer()
            Task { await playOpponentMove() }
        } catch {
            errorMessage = String(localized: "tactics.error_load")
        }
    }

    private func attemptMove(from origin: Square, to target: Square, promotion: PieceKind? = nil) {
        hintMove = nil
        var move = ChessMove(from: origin, to: target)
        if session.moveNeedsPromotion(move) {
            guard let promotion else {
                // The player must choose the promotion piece; the choice UI
                // is up while the move itself waits.
                pendingPromotion = (origin, target)
                return
            }
            move = ChessMove(from: origin, to: target, promotion: promotion)
        }
        // The expected move is trusted-legal (from the puzzle line), so accept
        // it even for moves the legality check would reject on partial data.
        // Any other move must be fully legal.
        let isExpected = move == session.expectedMove
        guard isExpected || session.isLegalUserMove(move) else {
            selectedSquare = nil
            return
        }

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
            errorMessage = String(localized: "tactics.error_apply")
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
            errorMessage = String(localized: "tactics.error_reply")
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
        if !ratingAppliedForPuzzle {
            ratingAppliedForPuzzle = true
            recordOutcome(.correct, for: currentIndex)
        }
        // The round history is independent of the rating flow: a hint on the
        // final puzzle must not lose the whole batch's history, and re-solving
        // the batch in review must not insert it a second time.
        let isBatchEnding = isLastPuzzle && !roundRecorded
        if isBatchEnding {
            roundRecorded = true
            progress?.recordRound(puzzles: puzzles, outcomes: results)
        }
        guard canUpdateRating, firstAttemptWasCorrect else {
            // The rating was already settled (hint) or never applied; either
            // way a finishing batch still gets its snapshot.
            if isBatchEnding { progress?.recordRatingSnapshot(value: userRating) }
            return
        }
        let cleanSolve = !hadMistake && hintMove == nil
        applySolveRating(solved: cleanSolve)
        // Snapshot only after this puzzle's delta landed, so the sample is the
        // batch's final rating.
        if isBatchEnding { progress?.recordRatingSnapshot(value: userRating) }
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

extension PuzzleSession {
    /// Stand-in session for a puzzle that failed to build. Shows an empty
    /// board in the error state instead of crashing the app.
    static func empty() -> PuzzleSession {
        try! PuzzleSession(puzzle: Puzzle(
            id: "empty",
            fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
            moves: ["e1e2", "e8e7"],
            rating: nil,
            themes: []
        ))
    }
}
