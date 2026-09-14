import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Round navigation: moving between the roundState.puzzles of the current round, looping
/// the finished round in review, and starting the next round once its window
/// opens.
extension TacticsTrainingStore {
    var puzzleCount: Int { roundState.puzzles.count }
    var puzzleNumber: Int { roundState.currentIndex + 1 }
    var isLastPuzzle: Bool { roundState.currentIndex >= roundState.puzzles.count - 1 }
    var isRoundComplete: Bool { isLastPuzzle && sessionState.currentPuzzleFinished }

    /// The puzzle has been completed at least once. Review navigation must not
    /// revoke this state or disable the Next puzzle action.
    /// Once the current puzzle is finished, navigation is available. At the
    /// end of a round we deliberately keep it enabled so the user can loop
    /// back through the completed round for review, even in Play roundState.mode.
    var canAdvanceToNextPuzzle: Bool {
        sessionState.currentPuzzleFinished && (!isLastPuzzle || isRoundComplete)
    }
    /// Whether the round window has expired — a new round can start right now.
    var isNewRoundAvailable: Bool {
        guard let tracker = roundState.tracker else { return false }
        return !tracker.isWithinWindow
    }

    /// The completed-puzzle result controls already contain the Next round
    /// action. In every other board state, surface a standalone CTA as soon
    /// as the round window has expired.
    var shouldShowNewRoundAction: Bool {
        isNewRoundAvailable && !sessionState.currentPuzzleFinished
    }

    /// "Unlocks at 3:10 PM" for the disabled button's hint and label; nil
    /// when there is nothing running to wait for.
    var nextRoundUnlockDescription: String? {
        guard let unlocksAt = roundState.tracker?.nextRoundUnlocksAt else { return nil }
        return String(
            format: NSLocalizedString("tactics.next_round_wait_until", comment: "Clock time when the next round unlocks"),
            unlocksAt.formatted(date: .omitted, time: .shortened)
        )
    }
    var canUpdateRating: Bool { roundState.mode == .play }
    var canInteractWithPuzzle: Bool { !inReview && (state == .waitingForMove || state == .incorrectMove) }

    /// The current puzzle's Lichess difficulty rating, if the data provides it.
    var currentPuzzleRating: Int? {
        roundState.puzzles.indices.contains(roundState.currentIndex) ? roundState.puzzles[roundState.currentIndex].rating : nil
    }

    /// How many times the current puzzle has been played on Lichess.
    var currentPuzzlePlayCount: Int? {
        roundState.puzzles.indices.contains(roundState.currentIndex) ? roundState.puzzles[roundState.currentIndex].playCount : nil
    }

    func nextPuzzle() {
        roundState.advance(
            currentPuzzleFinished: sessionState.currentPuzzleFinished,
            pacing: pacing,
            loadPuzzle: { [weak self] index in self?.loadPuzzle(at: index) }
        )
    }

    /// Starts a fresh round once the current window has expired. This guard is
    /// deliberately in the view model as well as the UI so another caller
    /// cannot bypass the cadence rule.
    func startNextRound() {
        guard isNewRoundAvailable else { return }
        roundState.mode = .play
        // Top up the library before selecting, in case the unattempted pool
        // can't fill a round; then reload on the main actor as before.
        Task { [provisioner = roundState.provisioner] in
            _ = await provisioner?.ensureRoundAvailable(minimum: roundState.dailyPuzzleCount)
            loadNextRound()
        }
    }

    private func loadNextRound() {
        let picked = roundState.selectNextRound(userRating: progressState.userRating)
        guard !picked.isEmpty else { return }
        progressState.beginRound(puzzleCount: picked.count)
        loadPuzzle(at: 0)
    }
}
