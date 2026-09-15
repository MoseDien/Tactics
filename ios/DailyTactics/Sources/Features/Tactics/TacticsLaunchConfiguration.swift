import PuzzleKit

/// Decides whether launch resumes the persisted batch or creates a new one.
/// A resumed incomplete batch is always Play mode; Review is only entered by
/// the explicit in-session "Next puzzle" transition after completion.
struct TacticsLaunchConfiguration: Equatable {
    let mode: TacticsMode
    let resumesActiveRound: Bool

    /// Any persisted round resumes in review — inside its window or expired
    /// alike: starting a fresh round is a user action (Next round), never an
    /// automatic one on launch. `isWithinWindow` only decides whether that
    /// button starts enabled.
    static func resolve(activePuzzleIDs: [String], isWithinWindow: Bool) -> Self {
        let resumes = !activePuzzleIDs.isEmpty
        return Self(mode: resumes ? .reviewRound : .play, resumesActiveRound: resumes)
    }
}
