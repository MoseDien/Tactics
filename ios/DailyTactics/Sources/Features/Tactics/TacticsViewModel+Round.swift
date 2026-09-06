import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Round navigation: moving between the puzzles of the current round, looping
/// the finished round in review, and starting the next round once its window
/// opens.
extension TacticsViewModel {
    var puzzleCount: Int { puzzles.count }
    var puzzleNumber: Int { currentIndex + 1 }
    var isLastPuzzle: Bool { currentIndex >= puzzles.count - 1 }
    var isRoundComplete: Bool { isLastPuzzle && currentPuzzleFinished }

    /// The puzzle has been completed at least once. Review navigation must not
    /// revoke this state or disable the Next puzzle action.
    /// Once the current puzzle is finished, navigation is available. At the
    /// end of a round we deliberately keep it enabled so the user can loop
    /// back through the completed round for review, even in Play mode.
    var canAdvanceToNextPuzzle: Bool {
        currentPuzzleFinished && (!isLastPuzzle || isRoundComplete)
    }
    var canStartNewRound: Bool { mode == .reviewRound && isNewRoundAvailable }
    /// Whether the round window has expired — a new round can start right now.
    /// Purely time-based; `canStartNewRound` additionally requires review mode.
    var isNewRoundAvailable: Bool { roundTracker?.isWithinWindow == false }
    var canUpdateRating: Bool { mode == .play }
    var canInteractWithPuzzle: Bool { !inReview && (state == .waitingForMove || state == .incorrectMove) }

    /// The current puzzle's Lichess difficulty rating, if the data provides it.
    var currentPuzzleRating: Int? {
        puzzles.indices.contains(currentIndex) ? puzzles[currentIndex].rating : nil
    }

    /// How many times the current puzzle has been played on Lichess.
    var currentPuzzlePlayCount: Int? {
        puzzles.indices.contains(currentIndex) ? puzzles[currentIndex].playCount : nil
    }

    func nextPuzzle() {
        guard !isAdvancing, (mode == .reviewRound || canAdvanceToNextPuzzle) else { return }
        isAdvancing = true
        // Reaching the end of a Play round and choosing Next puzzle means the
        // user is reviewing that completed round. Keep the mode indicator and
        // rating rules aligned with this transition.
        if mode == .play && isRoundComplete {
            mode = .reviewRound
        }
        let shouldLoopRound = mode == .reviewRound || isRoundComplete
        let target = shouldLoopRound ? (currentIndex + 1) % puzzles.count : currentIndex + 1
        // A brief beat before the next puzzle appears so the transition reads
        // as deliberate rather than an instant snap. Re-entry is blocked until
        // the load completes so repeated taps can't skip puzzles.
        Task {
            try? await Task.sleep(for: pacing.nextPuzzleDelay)
            currentIndex = target
            loadPuzzle(at: target)
            isAdvancing = false
        }
    }

    /// Starts a fresh round only after the user explicitly taps Next round.
    /// Expiry alone never changes Review mode.
    func startNextRound() {
        if roundTracker?.isWithinWindow == true {
            // The current round is still inside its time window: surface why
            // nothing new is coming and stay on the round being reviewed.
            roundCooldownMessage = String(localized: "tactics.round_cooldown")
            return
        }
        roundCooldownMessage = nil
        mode = .play
        // Top up the library before selecting, in case the unattempted pool
        // can't fill a round; then reload on the main actor as before.
        Task { [provisioner] in
            _ = await provisioner?.ensureRoundAvailable(minimum: dailyPuzzleCount)
            loadNextRound()
        }
    }

    private func loadNextRound() {
        guard let progress else { return }
        var selector = RoundSelector()
        let previousBatchIDs = Set(roundTracker?.activePuzzleIDs() ?? [])
        let picked = selector.select(
            library: progress.allPuzzles(),
            attempted: progress.attemptedIDs(),
            difficulty: difficultyStore?.current ?? .medium,
            userRating: userRating,
            count: dailyPuzzleCount,
            excluding: previousBatchIDs
        )
        guard !picked.isEmpty else { return }
        puzzles = picked
        roundTracker?.begin(picked)
        results = Array(repeating: nil, count: picked.count)
        roundRecorded = false
        currentIndex = 0
        loadPuzzle(at: 0)
    }
}
