import Foundation

/// Difficulty selection for new rounds, relative to the user's rating.
public enum DifficultyMode: String, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    public var id: String { rawValue }
    public var localizedKey: String { "settings.difficulty_\(rawValue)" }
}
