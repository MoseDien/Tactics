import Foundation
import Observation
import PuzzleKit

/// Observable wrapper over the round window. Owns the clock (injectable) so
/// `isWithinWindow` is testable without sleeping, and schedules a single
/// wake-up at expiry so the Next-round button unlocks on time without any
/// polling timer in the view.
@MainActor
@Observable
final class RoundTracker {
    private let state: any RoundStateRepository
    private let now: @Sendable () -> Date
    private var expiryTask: Task<Void, Never>?

    /// Recomputed from the persisted start time; observers see it flip.
    private(set) var isWithinWindow: Bool = false

    init(state: any RoundStateRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.state = state
        self.now = now
    }

    /// Reads persisted state (app launch) and starts the expiry watch.
    func restore() {
        refresh()
        watchExpiry()
    }

    /// Begins a new round at the current instant and watches its expiry.
    func begin(_ puzzles: [Puzzle]) {
        state.begin(puzzles, at: now())
        refresh()
        watchExpiry()
    }

    func activePuzzleIDs() -> [String] {
        state.activePuzzleIDs()
    }

    func currentPuzzles(from library: [Puzzle]) -> [Puzzle] {
        RoundLookup.puzzles(withIDs: state.activePuzzleIDs(), in: library)
    }

    private func refresh() {
        guard let start = state.startTime() else {
            isWithinWindow = false
            return
        }
        isWithinWindow = RoundWindow(startedAt: start).contains(now())
    }

    /// One scheduled wake-up at window expiry (no periodic timer). Replacing
    /// a pending watch cancels it first.
    private func watchExpiry() {
        expiryTask?.cancel()
        guard let start = state.startTime() else { return }
        let remaining = RoundWindow(startedAt: start).secondsRemaining(at: now())
        guard remaining > 0 else {
            isWithinWindow = false
            return
        }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.1))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
