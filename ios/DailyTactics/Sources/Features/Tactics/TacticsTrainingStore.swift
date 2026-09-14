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
    let sessionState: TacticsSessionStore
    let progressState: TacticsProgressStore
    var pacing: TacticsPacing = TacticsPacing()

    /// Production initializer: selects the opening round through the
    /// repositories (falling back to the bundled samples on an empty library)
    /// and takes over the injected round tracker.
    convenience init(dependencies: AppDependencies, dailyPuzzleCount: Int = 5, mode modeParam: TacticsMode = .play) {
        let data = dependencies.data
        var round: [Puzzle]
        if modeParam == .reviewRound {
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
        if modeParam == .play { dependencies.round.begin(round) }
        self.init(dataset: round, progress: data, ratingStore: dependencies.userRating, dailyPuzzleCount: dailyPuzzleCount, mode: modeParam)
        roundState.tracker = dependencies.round
        roundState.difficultyStore = dependencies.difficulty
        roundState.provisioner = dependencies.provisioner
        pacing = dependencies.pacing
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
            sessionState.errorMessage = String(localized: "tactics.error_load")
        }
        sessionState.boardGeneration += 1
        orientBoardToPlayer()
    }

    /// Flip the board between the two playing perspectives.
    func toggleBoardFlip() {
sessionState.isBoardFlipped.toggle()
    }

    /// Favorite (or un-favorite) the current puzzle. Only offered once the
    /// puzzle is finished; works identically in play and review modes and
    /// never touches scoring.
    func toggleFavorite() {
        guard sessionState.currentPuzzleFinished else { return }
        let id = roundState.puzzles[roundState.currentIndex].id
        let next = !sessionState.isCurrentFavorite
        roundState.repositories?.setFavorite(id, next)
        sessionState.isCurrentFavorite = next
    }

    /// Orient the board so the player's own pieces are at the bottom. Called on
    /// every puzzle load so the user always starts from their perspective.
    func orientBoardToPlayer() {
        sessionState.isBoardFlipped = sessionState.session.userColor == .black
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

    var state: PuzzleSessionState { sessionState.session.state }
    var playerColor: PieceColor { sessionState.session.userColor }

    /// Test hook: the live session value.
    func sessionForTest() -> PuzzleSession { sessionState.session }

    /// Test hook: whether the promotion picker is up.
    func pendingPromotionForTest() -> (from: Square, to: Square)? { sessionState.pendingPromotion }
    var headerTitle: String { String(localized: state == .solved ? "tactics.puzzle_complete" : "tactics.your_turn") }
    var headerSubtitle: String {
        String(localized: playerColor == .white ? "tactics.find_best_white" : "tactics.find_best_black")
    }

    var feedbackState: TacticsFeedbackState {
        if sessionState.errorMessage != nil {
            return .error(message: sessionState.errorMessage ?? "")
        }
        if sessionState.currentPuzzleFinished {
            return isLastPuzzle ? .trainingComplete : .puzzleComplete
        }
        if inReview && state != .solved {
            return .reviewing
        }

        switch state {
        case .waitingForMove:
            // No instruction text while simply waiting — the header already
            // says whose move it is. Only the hint surfaces guidance here.
            return sessionState.hintMove == nil ? .idle : .instruction(message: String(localized: "tactics.hint_instruction"), systemImage: "info.circle")
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
        guard state == .opponentMoving, sessionState.session.currentMoveIndex == 0 else { return }
        Task { await playOpponentMove() }
    }

}
