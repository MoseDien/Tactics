import Foundation
import Observation
import ChessCore
import PuzzleKit

/// Composes the training stores into view-specific view models.
@MainActor
@Observable
final class TacticsScreenViewModel {
    let training: TacticsTrainingStore
    let board: TacticsBoardViewModel
    let header: TacticsHeaderViewModel
    let controls: TacticsControlsViewModel
    let rating: TacticsRatingViewModel
    let progress: TacticsProgressViewModel
    let roundActions: TacticsRoundActionsViewModel
    let messages: TacticsMessageAreaViewModel
    let promotion: TacticsPromotionViewModel

    init(training: TacticsTrainingStore) {
        self.training = training
        board = TacticsBoardViewModel(training: training)
        header = TacticsHeaderViewModel(training: training)
        controls = TacticsControlsViewModel(training: training)
        rating = TacticsRatingViewModel(training: training)
        progress = TacticsProgressViewModel(training: training)
        roundActions = TacticsRoundActionsViewModel(training: training)
        messages = TacticsMessageAreaViewModel(training: training)
        promotion = TacticsPromotionViewModel(training: training)
    }

    func start() { training.start() }
    var currentPuzzle: Puzzle { training.roundState.puzzles[training.roundState.currentIndex] }
}

@MainActor
@Observable
final class TacticsBoardViewModel {
    private let training: TacticsTrainingStore
    private let session: TacticsSessionStore
    init(training: TacticsTrainingStore) {
        self.training = training
        session = training.sessionState
    }

    var position: [Square: Piece] { session.displayedPosition }
    var selectedSquare: Square? { session.selectedSquare }
    var hintMove: ChessMove? { session.hintMove }
    var lastMove: ChessMove? { session.lastMove }
    var isFlipped: Bool { session.isBoardFlipped }
    var animation: BoardAnimation {
        BoardAnimation(
            arrival: session.animatedArrival,
            boardGeneration: session.boardGeneration,
            moveRevision: session.boardMoveRevision,
            isSnapback: session.isSnapbackRender
        )
    }
    func select(_ square: Square) { training.select(square) }
}

@MainActor
@Observable
final class TacticsHeaderViewModel {
    private let training: TacticsTrainingStore
    private let round: TacticsRoundStore
    init(training: TacticsTrainingStore) {
        self.training = training
        round = training.roundState
    }

    var puzzleNumber: Int { round.puzzleNumber }
    var puzzleCount: Int { round.puzzleCount }
    var playerColor: PieceColor { training.playerColor }
    var title: String { training.headerTitle }
    var subtitle: String { training.headerSubtitle }
    var rating: Int? { training.currentPuzzleRating }
    var playCount: Int? { training.currentPuzzlePlayCount }
}

@MainActor
@Observable
final class TacticsControlsViewModel {
    private let training: TacticsTrainingStore
    private let session: TacticsSessionStore
    private let round: TacticsRoundStore
    init(training: TacticsTrainingStore) {
        self.training = training
        session = training.sessionState
        round = training.roundState
    }

    var currentMoveNumber: Int { training.currentMoveNumber }
    var totalUserMoves: Int { training.totalUserMoves }
    var mode: TacticsMode { round.mode }
    var isFavorite: Bool { session.isCurrentFavorite }
    var isFinished: Bool { session.currentPuzzleFinished }
    var canUseHint: Bool { training.hintEnabled }
    var canReviewPuzzle: Bool { training.canReviewCurrentPuzzle }
    func flipBoard() { training.toggleBoardFlip() }
    func toggleFavorite() { training.toggleFavorite() }
    func requestHint() { training.requestHint() }
}

@MainActor
@Observable
final class TacticsRatingViewModel {
    private let progress: TacticsProgressStore
    init(training: TacticsTrainingStore) { progress = training.progressState }
    var rating: Int { progress.userRating }
    var latestDelta: Int? { progress.lastRatingDelta }
}

@MainActor
@Observable
final class TacticsProgressViewModel {
    private let round: TacticsRoundStore
    private let progress: TacticsProgressStore
    init(training: TacticsTrainingStore) {
        round = training.roundState
        progress = training.progressState
    }
    var outcomes: [PuzzleOutcome?] { progress.outcomes }
    var currentIndex: Int { round.currentIndex }
}

@MainActor
@Observable
final class TacticsRoundActionsViewModel {
    private let training: TacticsTrainingStore
    private let round: TacticsRoundStore
    init(training: TacticsTrainingStore) {
        self.training = training
        round = training.roundState
    }

    var feedbackState: TacticsFeedbackState { training.feedbackState }
    var shouldShowNewRoundAction: Bool { training.shouldShowNewRoundAction }
    var showsCompletedRoundAction: Bool {
        round.mode == .reviewRound || training.isRoundComplete
    }
    var isNewRoundAvailable: Bool { round.isNewRoundAvailable }
    func nextPuzzle() { training.nextPuzzle() }
    func startNextRound() { training.startNextRound() }
}

@MainActor
@Observable
final class TacticsMessageAreaViewModel {
    private let training: TacticsTrainingStore
    private let round: TacticsRoundStore
    private let session: TacticsSessionStore
    init(training: TacticsTrainingStore) {
        self.training = training
        round = training.roundState
        session = training.sessionState
    }

    var feedbackState: TacticsFeedbackState { training.feedbackState }
    var currentMoveNumber: Int { training.currentMoveNumber }
    var totalUserMoves: Int { training.totalUserMoves }
    var showsNextRoundUnlock: Bool {
        session.currentPuzzleFinished
            && (round.mode == .reviewRound || training.isRoundComplete)
            && !round.isNewRoundAvailable
    }
    var nextRoundUnlockDescription: String? { round.nextRoundUnlockDescription }
}

@MainActor
@Observable
final class TacticsPromotionViewModel {
    private let training: TacticsTrainingStore
    init(training: TacticsTrainingStore) { self.training = training }
    var pendingPromotion: (from: Square, to: Square)? { training.sessionState.pendingPromotion }
    var playerColor: PieceColor { training.playerColor }
    func choose(_ kind: PieceKind) { training.choosePromotion(kind) }
}
