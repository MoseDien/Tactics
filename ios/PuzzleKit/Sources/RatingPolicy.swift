import Foundation

/// Elo-style puzzle rating policy. Pure and Sendable: the caller owns the
/// stored rating and persistence.
public struct PuzzleRatingCalculator: Sendable {
    public let kFactor: Double

    public init(kFactor: Double = 32) {
        self.kFactor = kFactor
    }

    public func expectedScore(userRating: Int, puzzleRating: Int) -> Double {
        1 / (1 + pow(10, Double(puzzleRating - userRating) / 400))
    }

    public func change(userRating: Int, puzzleRating: Int, solved: Bool) -> Int {
        let expected = expectedScore(userRating: userRating, puzzleRating: puzzleRating)
        let actual = solved ? 1.0 : 0.0
        let delta = Int((kFactor * (actual - expected)).rounded())
        return delta == 0 ? (solved ? 1 : -1) : delta
    }
}
