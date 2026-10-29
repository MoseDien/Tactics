import Foundation
import Observation
import PuzzleKit

/// Home-card presentation state over the session training store: round
/// progress, review status, rating, and the new-round window.
@MainActor
@Observable
final class HomeViewModel {
    private let training: TacticsTrainingStore
    private let round: TacticsRoundStore

    init(training: TacticsTrainingStore) {
        self.training = training
        round = training.roundState
    }

    /// The round plays through, then loops in review — the card shows the
    /// review status once either condition holds.
    var isReviewingRound: Bool {
        round.mode == .reviewRound || training.isRoundComplete
    }

    var puzzleNumber: Int { round.puzzleNumber }
    var puzzleCount: Int { round.puzzleCount }
    var outcomes: [PuzzleOutcome?] { training.progressState.outcomes }
    var solvedCount: Int { outcomes.filter { $0 == .correct }.count }
    var userRating: Int { training.progressState.userRating }
    var isNewRoundAvailable: Bool { round.isNewRoundAvailable }
    var nextRoundUnlockDescription: String? { round.nextRoundUnlockDescription }
}
