import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Batch navigation: moving between the puzzles of the current batch, looping
/// the finished batch in review, and starting the next batch once its window
/// opens.
extension TacticsViewModel {
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
    var canStartNewBatch: Bool { mode == .reviewBatch && isNewBatchAvailable }
    /// Whether the batch window has expired — a new batch can start right now.
    /// Purely time-based; `canStartNewBatch` additionally requires review mode.
    var isNewBatchAvailable: Bool { batchTracker?.isWithinWindow == false }
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
            try? await Task.sleep(for: pacing.nextPuzzleDelay)
            currentIndex = target
            loadPuzzle(at: target)
            isAdvancing = false
        }
    }

    /// Starts a fresh batch only after the user explicitly taps Next batch.
    /// Expiry alone never changes Review mode.
    func startNextBatch() {
        if batchTracker?.isWithinWindow == true {
            // The current batch is still inside its time window: surface why
            // nothing new is coming and stay on the batch being reviewed.
            batchCooldownMessage = String(localized: "tactics.batch_cooldown")
            return
        }
        batchCooldownMessage = nil
        mode = .play
        // Top up the library before selecting, in case the unattempted pool
        // can't fill a batch; then reload on the main actor as before.
        Task { [provisioner] in
            _ = await provisioner?.ensureBatchAvailable(minimum: dailyPuzzleCount)
            loadNextRound()
        }
    }

    private func loadNextRound() {
        guard let progress else { return }
        var selector = RoundSelector()
        let previousBatchIDs = Set(batchTracker?.activePuzzleIDs() ?? [])
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
        batchTracker?.begin(picked)
        results = Array(repeating: nil, count: picked.count)
        roundRecorded = false
        currentIndex = 0
        loadPuzzle(at: 0)
    }
}
