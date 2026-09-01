import Foundation
import PuzzleKit

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
