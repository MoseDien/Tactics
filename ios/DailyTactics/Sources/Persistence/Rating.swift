import Foundation

struct PuzzleRatingCalculator: Sendable {
    let kFactor: Double

    init(kFactor: Double = 32) {
        self.kFactor = kFactor
    }

    func expectedScore(userRating: Int, puzzleRating: Int) -> Double {
        1 / (1 + pow(10, Double(puzzleRating - userRating) / 400))
    }

    func change(userRating: Int, puzzleRating: Int, solved: Bool) -> Int {
        let expected = expectedScore(userRating: userRating, puzzleRating: puzzleRating)
        let actual = solved ? 1.0 : 0.0
        let delta = Int((kFactor * (actual - expected)).rounded())
        return delta == 0 ? (solved ? 1 : -1) : delta
    }
}

@MainActor
final class UserRatingStore {
    private let defaults: UserDefaults
    private let key = "dailytactics.userRating"
    private let initialRating = 1500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var rating: Int {
        let stored = defaults.integer(forKey: key)
        return stored == 0 ? initialRating : stored
    }

    func apply(delta: Int) -> Int {
        let updated = min(3000, max(400, rating + delta))
        defaults.set(updated, forKey: key)
        return updated
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    func set(rating: Int) {
        let normalized = min(3000, max(400, rating))
        defaults.set(normalized, forKey: key)
    }
}
