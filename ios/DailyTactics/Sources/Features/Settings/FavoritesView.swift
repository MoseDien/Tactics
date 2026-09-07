import SwiftUI
import PuzzleKit
import TacticsData

/// The favorited puzzles, newest favorite first. Each row shows the puzzle's
/// difficulty stars, id, rating/play count and its themes; tapping opens the
/// single-puzzle replay.
struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var favorites: [(puzzle: Puzzle, favoritedAt: Date?)] = []

    var body: some View {
        NavigationStack {
            List(favorites, id: \.puzzle.id) { entry in
                NavigationLink {
                    ReviewPuzzleView(puzzle: entry.puzzle)
                } label: {
                    favoriteRow(entry)
                }
            }
            .overlay { if favorites.isEmpty { emptyState } }
            .navigationTitle(String(localized: "settings.favorites"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(String(localized: "common.done")) { dismiss() } }
            .task { reload() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "favorites.empty"),
            systemImage: "heart",
            description: Text(String(localized: "favorites.empty_hint"))
        )
    }

    /// One favorite: difficulty stars on the left; id, stats, the side the
    /// player had and the favorite date in the middle; theme on the right.
    private func favoriteRow(_ entry: (puzzle: Puzzle, favoritedAt: Date?)) -> some View {
        let puzzle = entry.puzzle
        return HStack(spacing: 12) {
            VStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { level in
                    Image(systemName: level < Self.difficultyLevel(for: puzzle.rating) ? "star.fill" : "star")
                        .font(.system(size: 7))
                        .foregroundStyle(level < Self.difficultyLevel(for: puzzle.rating) ? Color.primary : Color.secondary.opacity(0.4))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("#\(puzzle.id)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let rating = puzzle.rating {
                    Text(String(
                        format: NSLocalizedString("favorites.stats", comment: "Puzzle rating and play count"),
                        rating, puzzle.playCount.map { $0.formatted() } ?? "–"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Label(
                        NSLocalizedString(playerColorKey(puzzle), comment: "Side the player holds"),
                        systemImage: playerColorSymbol(puzzle)
                    )
                    if let date = entry.favoritedAt {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "heart")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let theme = puzzle.themes.first {
                Text(themeName(theme))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(entry))
    }

    /// The side the puzzle asks the player to move for, read off the FEN's
    /// side to move (the machine opens, so the user holds its opponent).
    private func playerColorKey(_ puzzle: Puzzle) -> String {
        guard let fenSide = puzzle.fen.split(separator: " ").dropFirst().first,
              fenSide == "w" || fenSide == "b"
        else { return "favorites.side_unknown" }
        return fenSide == "w" ? "favorites.side_black" : "favorites.side_white"
    }

    private func playerColorSymbol(_ puzzle: Puzzle) -> String {
        guard let fenSide = puzzle.fen.split(separator: " ").dropFirst().first,
              fenSide == "w" || fenSide == "b"
        else { return "questionmark" }
        return fenSide == "w" ? "circle.fill" : "circle"
    }

    private func reload() {
        let library = dependencies.data.allPuzzles()
        let stamps = dependencies.data.favoriteStamps()
        // Newest favorites first; puzzles without a stamp (legacy rows) sink
        // to the bottom in id order.
        favorites = library
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

    private func rowAccessibilityLabel(_ entry: (puzzle: Puzzle, favoritedAt: Date?)) -> String {
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

    private func themeName(_ theme: PuzzleTheme) -> String {
        NSLocalizedString("theme.\(theme.rawValue)", comment: "Puzzle theme name")
    }
}
