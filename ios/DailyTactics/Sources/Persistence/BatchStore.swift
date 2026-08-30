import Foundation

enum BatchConfiguration {
    static let puzzleCount = 5
    static let batchDuration: TimeInterval = 10 * 60
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
    static func begin(with puzzles: [Puzzle]) {
        UserDefaults.standard.set(Date.now, forKey: startKey)
        UserDefaults.standard.set(puzzles.map(\.id), forKey: puzzleIDsKey)
    }
}
