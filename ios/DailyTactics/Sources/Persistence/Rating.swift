import Foundation

struct RatingLevel: Codable, Hashable, Sendable {
    let lowerBound: Int

    init(rating: Int) {
        lowerBound = min(1900, max(1000, (rating / 100) * 100))
    }

    init(lowerBound: Int) {
        self.lowerBound = min(1900, max(1000, lowerBound))
    }

    init?(rawValue: String) {
        guard let value = Int(rawValue), stride(from: 1000, through: 1900, by: 100).contains(value) else {
            return nil
        }
        lowerBound = value
    }

    var upperBound: Int { lowerBound + 100 }
    var rawValue: String { "\(lowerBound)" }
    var ratingRange: Range<Int> { lowerBound..<upperBound }
}

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
    private let levelKey = "dailytactics.ratingLevel"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var rating: Int {
        let stored = defaults.integer(forKey: key)
        return stored == 0 ? initialRating : stored
    }

    var level: RatingLevel { RatingLevel(rawValue: defaults.string(forKey: levelKey) ?? "") ?? RatingLevel(rating: rating) }

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
        defaults.set(RatingLevel(rating: normalized).rawValue, forKey: levelKey)
    }
}
