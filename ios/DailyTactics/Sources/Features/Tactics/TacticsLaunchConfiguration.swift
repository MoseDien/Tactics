/// Cold-launch routing for the persisted round. The stored mode label is
/// authoritative — `begin` writes "play", finishing the last puzzle flips it
/// to "review"; rows written before the field existed fall back to the
/// cursor (past the last puzzle = complete). Launch never creates a round —
/// `Next round` is the only path to a fresh batch, and the window only
/// decides whether that button starts enabled.
struct TacticsLaunchConfiguration: Equatable {
    let mode: TacticsMode
    let resumesActiveRound: Bool

    static func resolve(activePuzzleIDs: [String], nextPuzzleIndex: Int, storedMode: String?) -> Self {
        guard !activePuzzleIDs.isEmpty else {
            return Self(mode: .play, resumesActiveRound: false)
        }
        let mode = storedMode.flatMap(TacticsMode.init(persistedLabel:))
            ?? (nextPuzzleIndex >= activePuzzleIDs.count ? .reviewRound : .play)
        return Self(mode: mode, resumesActiveRound: true)
    }
}

extension TacticsMode {
    /// The literal kept in `dailytactics.activeRoundMode`.
    var persistedLabel: String { self == .play ? "play" : "review" }

    init?(persistedLabel: String) {
        switch persistedLabel {
        case "play": self = .play
        case "review": self = .reviewRound
        default: return nil
        }
    }
}
