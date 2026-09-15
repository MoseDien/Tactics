/// Cold-launch routing for the persisted round. An incomplete round resumes
/// in Play at its saved cursor; a completed one resumes in Review. Launch
/// never creates a round — `Next round` is the only path to a fresh batch,
/// and the window only decides whether that button starts enabled.
struct TacticsLaunchConfiguration: Equatable {
    let mode: TacticsMode
    let resumesActiveRound: Bool

    static func resolve(activePuzzleIDs: [String], nextPuzzleIndex: Int) -> Self {
        guard !activePuzzleIDs.isEmpty else {
            return Self(mode: .play, resumesActiveRound: false)
        }
        let complete = nextPuzzleIndex >= activePuzzleIDs.count
        return Self(mode: complete ? .reviewRound : .play, resumesActiveRound: true)
    }
}
