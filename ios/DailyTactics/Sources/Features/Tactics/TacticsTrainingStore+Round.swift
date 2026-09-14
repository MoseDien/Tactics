import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Round navigation: between puzzles, looping the finished round, starting
/// the next one once its window opens.
extension TacticsTrainingStore {
    var puzzleCount: Int { roundState.puzzles.count }
    var puzzleNumber: Int { roundState.currentIndex + 1 }
    var isLastPuzzle: Bool { roundState.currentIndex >= roundState.puzzles.count - 1 }
    var isRoundComplete: Bool { isLastPuzzle && sessionState.currentPuzzleFinished }

    /// Stays enabled at the end of a round so the player can loop back in review.
    var canAdvanceToNextPuzzle: Bool {
        sessionState.currentPuzzleFinished && (!isLastPuzzle || isRoundComplete)
    }
    /// Whether the round window has expired — a new round can start right now.
    var isNewRoundAvailable: Bool {
        guard let tracker = roundState.tracker else { return false }
        return !tracker.isWithinWindow
    }

    /// Standalone CTA in every non-completed state once the window expired.
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

    var currentPuzzleRating: Int? {
        roundState.puzzles.indices.contains(roundState.currentIndex) ? roundState.puzzles[roundState.currentIndex].rating : nil
    }

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

    /// The window guard here mirrors the disabled button: neither alone suffices.
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
