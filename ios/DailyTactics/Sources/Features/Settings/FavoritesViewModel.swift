import Foundation
import PuzzleKit
import ChessCore
import TacticsData

/// Favorites list state and row derivations.
@MainActor
@Observable
final class FavoritesViewModel {
    let dependencies: AppDependencies
    private(set) var entries: [(puzzle: Puzzle, favoritedAt: Date?)] = []

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// Newest first; untimestamped legacy rows sink in id order.
    func reload() {
        let library = dependencies.data.allPuzzles()
        let stamps = dependencies.data.favoriteStamps()
        entries = library
            .filter { stamps[$0.id] != nil }
            .map { ($0, stamps[$0.id]) }
            .sorted { lhs, rhs in
                switch (lhs.1, rhs.1) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.0.id < rhs.0.id
                }
            }
    }

    // MARK: Row display fields

    /// FEN side-to-move's opponent (the machine opens).
    func playerColorKey(for puzzle: Puzzle) -> String {
        guard let side = fenSide(for: puzzle) else { return "favorites.side_unknown" }
        return side == "w" ? "favorites.side_black" : "favorites.side_white"
    }

    func playerColorSymbol(for puzzle: Puzzle) -> String {
        guard let side = fenSide(for: puzzle) else { return "questionmark" }
        return side == "w" ? "circle.fill" : "circle"
    }

    func themeName(_ theme: PuzzleTheme) -> String {
        NSLocalizedString("theme.\(theme.rawValue)", comment: "Puzzle theme name")
    }

    func rowAccessibilityLabel(for entry: (puzzle: Puzzle, favoritedAt: Date?)) -> String {
        String(
            format: NSLocalizedString("favorites.row_accessibility", comment: "Favorite row summary"),
            entry.puzzle.id, entry.puzzle.rating ?? 0
        )
    }

    /// Same star mapping as the training header.
    static func difficultyLevel(for rating: Int?) -> Int {
        guard let rating else { return 3 }
        return min(5, max(1, (rating - 800) / 240 + 1))
    }

    private func fenSide(for puzzle: Puzzle) -> Substring? {
        guard let side = puzzle.fen.split(separator: " ").dropFirst().first,
              side == "w" || side == "b"
        else { return nil }
        return side
    }
}
