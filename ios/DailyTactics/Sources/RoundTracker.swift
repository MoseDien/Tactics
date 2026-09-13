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

    /// When the current window ends (the next round unlocks), if a round is
    /// persisted and still running. The UI shows this instant as a clock
    /// time rather than a countdown, so it stays truthful without ticking.
    var nextRoundUnlocksAt: Date? {
        guard let start = state.startTime() else { return nil }
        let end = RoundWindow(startedAt: start).expiresAt
        return end > now() ? end : nil
    }

    /// Recomputes the window from the persisted start time. Public so the app
    /// can re-check on lifecycle events (foreground, screen entry) — the
    /// scheduled expiry watch alone misses time passed while suspended.
    func refresh() {
        guard let start = state.startTime() else {
            isWithinWindow = false
            #if DEBUG
            print("[RoundTracker] refresh: no persisted start time → isWithinWindow=false")
            #endif
            return
        }
        let now = now()
        let window = RoundWindow(startedAt: start)
        isWithinWindow = window.contains(now)
        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let remaining = window.secondsRemaining(at: now)
        let state = remaining > 0
            ? String(format: "inside window, %.1fs remaining", remaining)
            : String(format: "expired %.1fs ago", -remaining)
        print("""
        [RoundTracker] refresh \
        { start: \(formatter.string(from: start)), \
        now: \(formatter.string(from: now)), \
        duration: \(window.duration)s, \
        expiresAt: \(formatter.string(from: window.expiresAt)), \
        \(state), \
        activePuzzles: \(state_activePuzzleCount()), \
        → isWithinWindow=\(isWithinWindow) }
        """)
        #endif
    }

    #if DEBUG
    private func state_activePuzzleCount() -> Int {
        state.activePuzzleIDs().count
    }
    #endif

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
