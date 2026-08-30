import Foundation

enum BatchConfiguration {
    static let puzzleCount = 5
    /// A new batch can be started every 4 hours (see docs/BUSINESS_LOGIC.md).
    static let batchDuration: TimeInterval = 4 * 60 * 60
}

enum BatchStore {
    static let startKey = "dailytactics.batchStartTime"
    static let puzzleIDsKey = "dailytactics.activeBatchPuzzleIDs"

    static func startTime() -> Date? {
        UserDefaults.standard.object(forKey: startKey) as? Date
    }
    static var isWithinDuration: Bool {
        guard let startTime = Self.startTime() else { return false }
        return Date.now.timeIntervalSince(startTime) < BatchConfiguration.batchDuration
    }
    static var activePuzzleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: puzzleIDsKey) ?? []
    }

    static func currentPuzzles(from library: [Puzzle]) -> [Puzzle] {
        var lookup: [String: Puzzle] = [:]
        lookup.reserveCapacity(library.count)
        // First occurrence wins, so a duplicated id in the library cannot trap.
        for puzzle in library {
            if lookup[puzzle.id] == nil { lookup[puzzle.id] = puzzle }
        }
        return activePuzzleIDs.compactMap { lookup[$0] }
    }
    static func begin(with puzzles: [Puzzle]) {
        UserDefaults.standard.set(Date.now, forKey: startKey)
        UserDefaults.standard.set(puzzles.map(\.id), forKey: puzzleIDsKey)
    }
}
