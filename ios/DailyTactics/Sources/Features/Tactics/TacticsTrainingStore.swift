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

enum TacticsMode: Equatable { case play, reviewRound }

/// Coordinator over the session/round/progress stores: cross-domain actions
/// (move submission, round navigation, scoring) live here.
@MainActor
@Observable
final class TacticsTrainingStore {
    let roundState: TacticsRoundStore
    let sessionState: TacticsSessionStore
    let progressState: TacticsProgressStore
    var pacing: TacticsPacing = TacticsPacing()

    convenience init(
        dependencies: AppDependencies,
        dailyPuzzleCount: Int = 5,
        mode modeParam: TacticsMode = .play,
        resumesActiveRound: Bool = false
    ) {
        let data = dependencies.data
        var round: [Puzzle]
        if resumesActiveRound || modeParam == .reviewRound {
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
        if modeParam == .play, !resumesActiveRound { dependencies.round.begin(round) }
        self.init(dataset: round, progress: data, ratingStore: dependencies.userRating, dailyPuzzleCount: dailyPuzzleCount, mode: modeParam)
        roundState.tracker = dependencies.round
        roundState.difficultyStore = dependencies.difficulty
        roundState.provisioner = dependencies.provisioner
        pacing = dependencies.pacing
        if resumesActiveRound {
            progressState.restoreRoundOutcomes(for: roundState.puzzles)
            restoreActiveRoundSession()
        }
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
            // One unusable data row falls back to the hand-verified samples.
            sessionState = TacticsSessionStore(session: (try? PuzzleSession(puzzle: Puzzle.samples[0])) ?? PuzzleSession.empty())
            sessionState.errorMessage = String(localized: "tactics.error_load")
        }
        sessionState.boardGeneration += 1
        orientBoardToPlayer()
    }

    func toggleBoardFlip() {
sessionState.isBoardFlipped.toggle()
    }

    /// Only offered once the puzzle is finished; never touches scoring.
    func toggleFavorite() {
        guard sessionState.currentPuzzleFinished else { return }
        let id = roundState.puzzles[roundState.currentIndex].id
        let next = !sessionState.isCurrentFavorite
        roundState.repositories?.setFavorite(id, next)
        sessionState.isCurrentFavorite = next
    }

    /// Player's pieces at the bottom; called on every puzzle load.
    func orientBoardToPlayer() {
        sessionState.isBoardFlipped = sessionState.session.userColor == .black
    }

    /// Build the session at the persisted cursor of the active round.
    private func restoreActiveRoundSession() {
        let index = roundState.restorePersistedCursor()
        guard roundState.puzzles.indices.contains(index) else { return }
        let puzzle = roundState.puzzles[index]
        guard let session = try? PuzzleSession(puzzle: puzzle) else {
            sessionState.errorMessage = String(localized: "tactics.error_load")
            return
        }
        sessionState.reset(
            with: session,
            favorite: roundState.repositories?.isFavorite(puzzle.id) ?? false
        )
        progressState.beginPuzzle()
    }

    // MARK: - Board state

    var position: [Square: Piece] { sessionState.position }
    var lastMove: ChessMove? { sessionState.lastMove }

    var displayedPosition: [Square: Piece] {
        sessionState.displayedPosition
    }

    var animatedArrival: [Square: Square] {
        sessionState.animatedArrival
    }

    var isSnapbackRender: Bool { sessionState.isSnapbackRender }

    var boardGenerationValue: Int { get { sessionState.boardGeneration } set { sessionState.boardGeneration = newValue } }
    var boardMoveRevisionValue: Int { get { sessionState.boardMoveRevision } set { sessionState.boardMoveRevision = newValue } }
    var boardGeneration: Int { sessionState.boardGeneration }
    var boardMoveRevision: Int { sessionState.boardMoveRevision }

    var state: PuzzleSessionState { sessionState.session.state }
    var playerColor: PieceColor { sessionState.session.userColor }

    func sessionForTest() -> PuzzleSession { sessionState.session }

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
