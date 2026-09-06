import Foundation
import PuzzleKit
import ChessCore
import Observation
import TacticsData

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

enum TacticsMode { case play, reviewRound }

@MainActor
@Observable
final class TacticsViewModel {
    /// Queries SwiftData at each round boundary.
    let dailyPuzzleCount: Int
    var mode: TacticsMode
    var puzzles: [Puzzle]
    var currentIndex: Int
    var session: PuzzleSession
    var selectedSquare: Square?
    var attemptedMove: ChessMove?
    /// The wrong move whose preview is being reverted in this render, so the
    /// board can slide the piece back to its origin instead of teleporting it.
    var snapbackMove: ChessMove?
    var hintMove: ChessMove?
    var errorMessage: String?
    /// Pending promotion: set when a pawn move reaches the last rank, cleared
    /// once the player picks a piece (or the move is cancelled by re-selection).
    var pendingPromotion: (from: Square, to: Square)?
    var progress: (any PuzzleDataRepositories)?
    weak var roundTracker: RoundTracker?
    var difficultyStore: DifficultyModeStore?
    var provisioner: (any PuzzleProvisioning)?
    var pacing: TacticsPacing = TacticsPacing()
    let ratingStore: UserRatingStore
    let ratingCalculator = PuzzleRatingCalculator()
    var hadMistake = false
    var ratingAppliedForPuzzle = false
    var firstAttemptWasCorrect = false
    var isAdvancing = false
    /// Whether this round has already been written to `RoundHistory`. The
    /// round is recorded exactly once per round — re-solving puzzles in review
    /// (or solving the last one after a hint) must not insert or skip a row.
    var roundRecorded = false
    /// Remains true after the puzzle is solved, even while the user scrubs
    /// backward through the solution during review.
    var currentPuzzleFinished = false
    var userRating: Int
    var lastRatingDelta: Int?
    var isBoardFlipped: Bool = false
    /// Message surfaced when the user taps "Next round" inside the cooldown
    /// window. Cleared on the next puzzle load.
    var roundCooldownMessage: String?
    /// Whether the current puzzle is favorited. Refreshed on every puzzle
    /// load; the heart button appears once the puzzle is finished.
    var isCurrentFavorite = false

    /// Per-puzzle outcome for the current round. `nil` = not yet attempted.
    var results: [PuzzleOutcome?] = []

    /// Production initializer: selects the opening round through the
    /// repositories (falling back to the bundled samples on an empty library)
    /// and takes over the injected round tracker.
    convenience init(dependencies: AppDependencies, dailyPuzzleCount: Int = 5, mode: TacticsMode = .play) {
        let data = dependencies.data
        var round: [Puzzle]
        if mode == .reviewRound {
            round = dependencies.round.currentPuzzles(from: data.allPuzzles())
        } else {
            var selector = RoundSelector()
            round = selector.select(
                library: data.allPuzzles(),
                attempted: data.attemptedIDs(),
                difficulty: dependencies.difficulty.current,
                userRating: dependencies.userRating.rating,
                count: dailyPuzzleCount
            )
        }
        if round.isEmpty { round = Puzzle.samples }
        if mode == .play { dependencies.round.begin(round) }
        self.init(dataset: round, progress: data, ratingStore: dependencies.userRating, dailyPuzzleCount: dailyPuzzleCount, mode: mode)
        self.roundTracker = dependencies.round
        self.difficultyStore = dependencies.difficulty
        self.provisioner = dependencies.provisioner
        self.pacing = dependencies.pacing
    }

    init(dataset: [Puzzle], progress: (any PuzzleDataRepositories)? = nil, ratingStore: UserRatingStore = UserRatingStore(), dailyPuzzleCount: Int = 5, mode: TacticsMode = .play) {
        let round = dataset.isEmpty ? Puzzle.samples : dataset
        self.dailyPuzzleCount = dailyPuzzleCount
        self.mode = mode
        self.progress = progress
        self.ratingStore = ratingStore
        userRating = ratingStore.rating
        self.puzzles = round
        results = Array(repeating: nil, count: round.count)
        roundRecorded = false
        currentIndex = 0
        do {
            session = try PuzzleSession(puzzle: round[0])
        } catch {
            // A puzzle that cannot build a session is unusable, but crashing
            // the app over one data row is worse: fall back to the samples,
            // which are hand-verified.
            session = (try? PuzzleSession(puzzle: Puzzle.samples[0])) ?? PuzzleSession.empty()
            errorMessage = String(localized: "tactics.error_load")
        }
        boardGenerationValue += 1
        orientBoardToPlayer()
    }

    /// Flip the board between the two playing perspectives.
    func toggleBoardFlip() {
        isBoardFlipped.toggle()
    }

    /// Favorite (or un-favorite) the current puzzle. Only offered once the
    /// puzzle is finished; works identically in play and review modes and
    /// never touches scoring.
    func toggleFavorite() {
        guard currentPuzzleFinished else { return }
        let id = puzzles[currentIndex].id
        let next = !isCurrentFavorite
        progress?.setFavorite(id, next)
        isCurrentFavorite = next
    }

    /// Orient the board so the player's own pieces are at the bottom. Called on
    /// every puzzle load so the user always starts from their perspective.
    func orientBoardToPlayer() {
        isBoardFlipped = session.userColor == .black
    }

    // MARK: - Board state

    var position: [Square: Piece] { session.board.pieces }
    var lastMove: ChessMove? { session.lastMove }

    /// Position shown on the board. While a wrong move is being demonstrated, the
    /// moved piece is shown on its target square; clearing `attemptedMove` slides
    /// it back (see `animatedArrival`).
    var displayedPosition: [Square: Piece] {
        guard let attempt = attemptedMove, let piece = position[attempt.from] else {
            return position
        }
        var preview = position
        preview.removeValue(forKey: attempt.from)
        preview[attempt.to] = piece
        return preview
    }

    /// The single source of truth for piece travel: for each square that just
    /// gained a piece this render, the square it visually arrived from.
    /// Covers committed moves, the wrong-move preview, its snap-back and the
    /// castling rook. Empty when nothing should slide: puzzle loads (no move
    /// attached — the board presents a ready position) and the opening move's
    /// landing (part of the puzzle's initialization).
    var animatedArrival: [Square: Square] {
        if let attempt = attemptedMove {
            // Wrong move being demonstrated: its piece slides to the target.
            return [attempt.to: attempt.from]
        }
        if let snap = snapbackMove {
            // The preview is reverting: the piece slides back to its origin.
            return [snap.from: snap.to]
        }
        // Every committed move slides, the machine's opening move included —
        // a load (lastMove == nil) presents the setup position in place, then
        // the opening move slides in like any other.
        guard let move = session.lastMove else { return [:] }
        var arrivals: [Square: Square] = [move.to: move.from]
        if let rook = session.castlingRookMove() {
            arrivals[rook.to] = rook.from
        }
        return arrivals
    }

    /// Increments on every puzzle load. The board bakes it into every piece id
    /// so a load presents brand-new views (fade-in transition; no carried-over
    /// views that could interpolate offsets across the load). Monotonic and
    /// never cleared, so unlike a one-render signal it has no lifecycle.
    var boardGenerationValue = 0
    var boardMoveRevisionValue = 0
    var boardGeneration: Int { boardGenerationValue }
    var boardMoveRevision: Int { boardMoveRevisionValue }

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
            return isRoundComplete ? .trainingComplete : .puzzleComplete
        }
    }

    // MARK: - Session actions

    func start() {
        guard state == .opponentMoving, session.currentMoveIndex == 0 else { return }
        Task { await playOpponentMove() }
    }

    func select(_ square: Square) {
        guard canInteractWithPuzzle else { return }
        if attemptedMove != nil {
            snapbackMove = attemptedMove
        }
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
}
