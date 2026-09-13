import Foundation
import Observation
import PuzzleKit
import TacticsData

/// State and dependencies scoped to one training round. Selection and loading
/// are coordinated by `TacticsTrainingStore`, because they must also reset the
/// current `TacticsSessionStore` and notify `TacticsProgressStore`.
@MainActor
@Observable
final class TacticsRoundStore {
    let dailyPuzzleCount: Int
    var mode: TacticsMode
    var puzzles: [Puzzle]
    var currentIndex = 0
    var isAdvancing = false
    var repositories: (any PuzzleDataRepositories)?
    var tracker: RoundTracker?
    var difficultyStore: DifficultyModeStore?
    var provisioner: (any PuzzleProvisioning)?

    init(
        puzzles: [Puzzle],
        repositories: (any PuzzleDataRepositories)?,
        dailyPuzzleCount: Int,
        mode: TacticsMode
    ) {
        self.puzzles = puzzles
        self.repositories = repositories
        self.dailyPuzzleCount = dailyPuzzleCount
        self.mode = mode
    }

    var puzzleCount: Int { puzzles.count }
    var puzzleNumber: Int { currentIndex + 1 }
    var isLastPuzzle: Bool { currentIndex >= puzzles.count - 1 }
    var isNewRoundAvailable: Bool { !(tracker?.isWithinWindow ?? true) }
    var nextRoundUnlockDescription: String? {
        guard let unlocksAt = tracker?.nextRoundUnlocksAt else { return nil }
        return String(
            format: NSLocalizedString("tactics.next_round_wait_until", comment: "Clock time when the next round unlocks"),
            unlocksAt.formatted(date: .omitted, time: .shortened)
        )
    }

    func advance(
        currentPuzzleFinished: Bool,
        pacing: TacticsPacing,
        loadPuzzle: @escaping @MainActor (Int) -> Void
    ) {
        let roundComplete = isLastPuzzle && currentPuzzleFinished
        guard !isAdvancing, (mode == .reviewRound || currentPuzzleFinished) else { return }
        isAdvancing = true
        if mode == .play, roundComplete { mode = .reviewRound }
        let target = mode == .reviewRound || roundComplete
            ? (currentIndex + 1) % puzzles.count
            : currentIndex + 1
        Task { @MainActor in
            try? await Task.sleep(for: pacing.nextPuzzleDelay)
            currentIndex = target
            loadPuzzle(target)
            isAdvancing = false
        }
    }

    func selectNextRound(userRating: Int) -> [Puzzle] {
        guard let repositories else { return [] }
        var selector = RoundSelector()
        let previousIDs = Set(tracker?.activePuzzleIDs() ?? [])
        let picked = selector.select(
            library: repositories.allPuzzles(),
            attempted: repositories.attemptedIDs(),
            difficulty: difficultyStore?.current ?? .medium,
            userRating: userRating,
            count: dailyPuzzleCount,
            excluding: previousIDs
        )
        guard !picked.isEmpty else { return [] }
        puzzles = picked
        currentIndex = 0
        tracker?.begin(picked)
        return picked
    }
}
