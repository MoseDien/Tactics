import PuzzleKit

/// Decides whether launch resumes the persisted batch or creates a new one.
/// A resumed incomplete batch is always Play mode; Review is only entered by
/// the explicit in-session "Next puzzle" transition after completion.
struct TacticsLaunchConfiguration: Equatable {
    let mode: TacticsMode
    let resumesActiveRound: Bool

    static func resolve(activePuzzleIDs: [String], isWithinWindow: Bool) -> Self {
        Self(mode: .play, resumesActiveRound: !activePuzzleIDs.isEmpty && isWithinWindow)
    }
}
