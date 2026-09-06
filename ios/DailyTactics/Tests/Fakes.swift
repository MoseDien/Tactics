import Foundation
import PuzzleKit

/// Mutable clock for time-dependent tests: advance `now` and assert, no
/// sleeping. Thread-safe so it can back the tracker's `@Sendable () -> Date`.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000)) {
        self.stored = now
    }

    var now: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func advance(_ interval: TimeInterval) { now = now.addingTimeInterval(interval) }
}

/// In-memory round state: the UserDefaults-free `RoundStateRepository` fake.
@MainActor
final class InMemoryRoundState: RoundStateRepository {
    private(set) var storedStart: Date?
    private(set) var storedIDs: [String] = []

    func startTime() -> Date? { storedStart }
    func activePuzzleIDs() -> [String] { storedIDs }
    func begin(_ puzzles: [Puzzle], at start: Date) {
        storedStart = start
        storedIDs = puzzles.map(\.id)
    }
}
