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
final class TacticsTrainingStore {
    let roundState: TacticsRoundStore
    var dailyPuzzleCount: Int { roundState.dailyPuzzleCount }
    var mode: TacticsMode { get { roundState.mode } set { roundState.mode = newValue } }
    var puzzles: [Puzzle] { get { roundState.puzzles } set { roundState.puzzles = newValue } }
    var currentIndex: Int { get { roundState.currentIndex } set { roundState.currentIndex = newValue } }
    let sessionState: TacticsSessionStore
    var session: PuzzleSession { get { sessionState.session } set { sessionState.session = newValue } }
    var selectedSquare: Square? { get { sessionState.selectedSquare } set { sessionState.selectedSquare = newValue } }
    var attemptedMove: ChessMove? { get { sessionState.attemptedMove } set { sessionState.attemptedMove = newValue } }
    /// The wrong move whose preview is being reverted in this render, so the
    /// board can slide the piece back to its origin instead of teleporting it.
    var snapbackMove: ChessMove? { get { sessionState.snapbackMove } set { sessionState.snapbackMove = newValue } }
    var hintMove: ChessMove? { get { sessionState.hintMove } set { sessionState.hintMove = newValue } }
    var errorMessage: String? { get { sessionState.errorMessage } set { sessionState.errorMessage = newValue } }
    /// Pending promotion: set when a pawn move reaches the last rank, cleared
    /// once the player picks a piece (or the move is cancelled by re-selection).
    var pendingPromotion: (from: Square, to: Square)? { get { sessionState.pendingPromotion } set { sessionState.pendingPromotion = newValue } }
    var progress: (any PuzzleDataRepositories)? { get { roundState.repositories } set { roundState.repositories = newValue } }
    /// The tracker is app-scoped and does not retain the view model, so keep a
    /// strong reference. The availability CTA must continue observing it after
    /// foregrounding rather than silently treating a released weak reference
    /// as a closed window.
    var roundTracker: RoundTracker? { get { roundState.tracker } set { roundState.tracker = newValue } }
    var difficultyStore: DifficultyModeStore? { get { roundState.difficultyStore } set { roundState.difficultyStore = newValue } }
    var provisioner: (any PuzzleProvisioning)? { get { roundState.provisioner } set { roundState.provisioner = newValue } }
    var pacing: TacticsPacing = TacticsPacing()
    let progressState: TacticsProgressStore
    var isAdvancing: Bool { get { roundState.isAdvancing } set { roundState.isAdvancing = newValue } }
    /// Remains true after the puzzle is solved, even while the user scrubs
    /// backward through the solution during review.
    var currentPuzzleFinished: Bool { get { sessionState.currentPuzzleFinished } set { sessionState.currentPuzzleFinished = newValue } }
    var isBoardFlipped: Bool { get { sessionState.isBoardFlipped } set { sessionState.isBoardFlipped = newValue } }
    /// Whether the current puzzle is favorited. Refreshed on every puzzle
    /// load; the heart button appears once the puzzle is finished.
    var isCurrentFavorite: Bool { get { sessionState.isCurrentFavorite } set { sessionState.isCurrentFavorite = newValue } }

    var userRating: Int { progressState.userRating }
    var lastRatingDelta: Int? { progressState.lastRatingDelta }
    var results: [PuzzleOutcome?] { progressState.outcomes }

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
        roundState = TacticsRoundStore(
            puzzles: round,
            repositories: progress,
            dailyPuzzleCount: dailyPuzzleCount,
            mode: mode
        )
        progressState = TacticsProgressStore(
            repositories: progress,
            ratingStore: ratingStore,
            puzzleCount: round.count
        )
        do {
            sessionState = TacticsSessionStore(session: try PuzzleSession(puzzle: round[0]))
        } catch {
            // A puzzle that cannot build a session is unusable, but crashing
            // the app over one data row is worse: fall back to the samples,
            // which are hand-verified.
            sessionState = TacticsSessionStore(session: (try? PuzzleSession(puzzle: Puzzle.samples[0])) ?? PuzzleSession.empty())
            errorMessage = String(localized: "tactics.error_load")
        }
        sessionState.boardGeneration += 1
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

    var position: [Square: Piece] { sessionState.position }
    var lastMove: ChessMove? { sessionState.lastMove }

    /// Position shown on the board. While a wrong move is being demonstrated, the
    /// moved piece is shown on its target square; clearing `attemptedMove` slides
    /// it back (see `animatedArrival`).
    var displayedPosition: [Square: Piece] {
        sessionState.displayedPosition
    }

    /// The single source of truth for piece travel: for each square that just
    /// gained a piece this render, the square it visually arrived from.
    /// Covers committed moves, the wrong-move preview, its snap-back and the
    /// castling rook. Empty when nothing should slide: puzzle loads (no move
    /// attached — the board presents a ready position) and the opening move's
    /// landing (part of the puzzle's initialization).
    var animatedArrival: [Square: Square] {
        sessionState.animatedArrival
    }

    /// True while this render's arrivals are revert slides (the wrong-move
    /// snap-back): the board plays them one-third faster than forward moves.
    var isSnapbackRender: Bool { sessionState.isSnapbackRender }

    /// Increments on every puzzle load. The board bakes it into every piece id
    /// so a load presents brand-new views (fade-in transition; no carried-over
    /// views that could interpolate offsets across the load). Monotonic and
    /// never cleared, so unlike a one-render signal it has no lifecycle.
    var boardGenerationValue: Int { get { sessionState.boardGeneration } set { sessionState.boardGeneration = newValue } }
    var boardMoveRevisionValue: Int { get { sessionState.boardMoveRevision } set { sessionState.boardMoveRevision = newValue } }
    var boardGeneration: Int { sessionState.boardGeneration }
    var boardMoveRevision: Int { sessionState.boardMoveRevision }

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

}
