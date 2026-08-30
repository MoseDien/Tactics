import Foundation

enum DifficultyMode: String, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
    var localizedKey: String { "settings.difficulty_\(rawValue)" }
}

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
