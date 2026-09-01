import Foundation

/// Pure batch selection: reproduces the historical `fetchUnattemptedRound`
/// chain — unattempted pool (minus `excluding`) → difficulty band → fallback
/// to the unattempted pool → fallback to the whole library — then shuffle and
/// prefix. Randomness is injected as a value-shuffling closure so the selector
/// itself stays Sendable and tests stay deterministic.
public struct RoundSelector: Sendable {
    /// Returns `count` elements of `source` in random order.
    public var shuffle: @Sendable ([Puzzle]) -> [Puzzle]

    public init(shuffle: @escaping @Sendable ([Puzzle]) -> [Puzzle] = { $0.shuffled() }) {
        self.shuffle = shuffle
    }

    public func select(
        library: [Puzzle],
        attempted: Set<String>,
        difficulty: DifficultyMode,
        userRating: Int,
        count: Int,
        excluding: Set<String> = []
    ) -> [Puzzle] {
        let pool = library.filter { !attempted.contains($0.id) && !excluding.contains($0.id) }
        let filtered: [Puzzle]
        switch difficulty {
        case .easy: filtered = pool.filter { ($0.rating ?? 0) <= userRating + 200 }
        case .hard: filtered = pool.filter { ($0.rating ?? Int.max) >= userRating - 200 }
        case .medium: filtered = pool
        }
        let source = filtered.count >= count ? filtered : (pool.count >= count ? pool : library.filter { !excluding.contains($0.id) })
        return Array(shuffle(source).prefix(min(count, source.count)))
    }
}
