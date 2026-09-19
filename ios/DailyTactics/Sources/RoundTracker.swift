import Foundation
import Observation
import PuzzleKit

/// Observable round-window wrapper: injectable clock (testable without
/// sleeping) plus one expiry wake-up (no polling timers).
@MainActor
@Observable
final class RoundTracker {
    private let state: any RoundStateRepository
    private let now: @Sendable () -> Date
    /// Injectable so the debug picker overrides the policy without the domain
    /// reading preferences.
    private let duration: @Sendable () -> TimeInterval
    private var expiryTask: Task<Void, Never>?

    private(set) var isWithinWindow: Bool = false

    init(
        state: any RoundStateRepository,
        now: @escaping @Sendable () -> Date = { .now },
        duration: @escaping @Sendable () -> TimeInterval = { RoundPolicy.roundDuration }
    ) {
        self.state = state
        self.now = now
        self.duration = duration
    }

    /// Launch: read persisted state and start the expiry watch.
    func restore() {
        refresh()
        watchExpiry()
    }

    func begin(_ puzzles: [Puzzle]) {
        state.begin(puzzles, at: now())
        refresh()
        watchExpiry()
    }

    func activePuzzleIDs() -> [String] {
        state.activePuzzleIDs()
    }

    func nextPuzzleIndex() -> Int { state.nextPuzzleIndex() }

    func setNextPuzzleIndex(_ index: Int) {
        state.setNextPuzzleIndex(index)
    }

    func roundMode() -> String? { state.roundMode() }
    func setRoundMode(_ mode: String) { state.setRoundMode(mode) }

    func currentPuzzles(from library: [Puzzle]) -> [Puzzle] {
        RoundLookup.puzzles(withIDs: state.activePuzzleIDs(), in: library)
    }

    var nextRoundUnlocksAt: Date? {
        guard let start = state.startTime() else { return nil }
        let end = RoundWindow(startedAt: start, duration: duration()).expiresAt
        return end > now() ? end : nil
    }

    /// Re-check on lifecycle events; the expiry sleep misses suspended time.
    func refresh() {
        guard let start = state.startTime() else {
            isWithinWindow = false
            #if DEBUG
            print("[RoundTracker] refresh: no persisted start time → isWithinWindow=false")
            #endif
            return
        }
        let now = now()
        let window = RoundWindow(startedAt: start, duration: duration())
        isWithinWindow = window.contains(now)
        #if DEBUG
        let clock: (Date) -> String = { $0.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))) }
        let remaining = window.secondsRemaining(at: now)
        let seconds = abs(remaining).formatted(.number.precision(.fractionLength(1)))
        let state = remaining > 0
            ? "inside window, \(seconds)s remaining"
            : "expired \(seconds)s ago"
        print("""
        [RoundTracker] refresh \
        { start: \(clock(start)), \
        now: \(clock(now)), \
        duration: \(window.duration)s, \
        expiresAt: \(clock(window.expiresAt)), \
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

    /// One wake-up at expiry; replacing a pending watch cancels it first.
    private func watchExpiry() {
        expiryTask?.cancel()
        guard let start = state.startTime() else { return }
        let remaining = RoundWindow(startedAt: start, duration: duration()).secondsRemaining(at: now())
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
