import Foundation
import PuzzleKit

/// Transitional static facade over the batch state; replaced by the injected
/// BatchTracker in phase 4 of the architecture remediation.
enum BatchStore {
    static let startKey = "dailytactics.batchStartTime"
    static let puzzleIDsKey = "dailytactics.activeBatchPuzzleIDs"

    static func startTime() -> Date? {
        UserDefaults.standard.object(forKey: startKey) as? Date
    }
    static var isWithinDuration: Bool {
        guard let startTime = Self.startTime() else { return false }
        return Date.now.timeIntervalSince(startTime) < BatchPolicy.batchDuration
    }
    static var activePuzzleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: puzzleIDsKey) ?? []
    }

    static func currentPuzzles(from library: [Puzzle]) -> [Puzzle] {
        BatchLookup.puzzles(withIDs: activePuzzleIDs, in: library)
    }
    static func begin(with puzzles: [Puzzle]) {
        UserDefaults.standard.set(Date.now, forKey: startKey)
        UserDefaults.standard.set(puzzles.map(\.id), forKey: puzzleIDsKey)
    }
}
