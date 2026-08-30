import Foundation

enum BatchConfiguration {
    static let puzzleCount = 5
    static let batchDuration: TimeInterval = 2 * 60
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
        let lookup = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        return activePuzzleIDs.compactMap { lookup[$0] }
    }
    static func begin(with puzzles: [Puzzle]) {
        UserDefaults.standard.set(Date.now, forKey: startKey)
        UserDefaults.standard.set(puzzles.map(\.id), forKey: puzzleIDsKey)
    }
}
