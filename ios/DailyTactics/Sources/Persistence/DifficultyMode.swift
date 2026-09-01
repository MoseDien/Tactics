import Foundation
import PuzzleKit

enum DifficultyModeStore {
    private static let key = "dailytactics.difficultyMode"

    static var current: DifficultyMode {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = DifficultyMode(rawValue: raw) else { return .medium }
        return mode
    }

    static func set(_ mode: DifficultyMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }
}
