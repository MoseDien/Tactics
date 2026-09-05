import SwiftUI
import PuzzleKit
import TacticsData

/// The favorited puzzles, newest favorite first. Each row shows the puzzle's
/// difficulty stars, id, rating/play count and its themes; tapping opens the
/// single-puzzle replay.
struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var favorites: [Puzzle] = []

    var body: some View {
        NavigationStack {
            List(favorites) { puzzle in
                NavigationLink {
                    ReviewPuzzleView(puzzle: puzzle)
                } label: {
                    favoriteRow(puzzle)
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

    /// One favorite: difficulty stars on the left, id and stats in the
    /// middle, themes as a trailing caption.
    private func favoriteRow(_ puzzle: Puzzle) -> some View {
        HStack(spacing: 12) {
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
        .accessibilityLabel(rowAccessibilityLabel(puzzle))
    }

    private func reload() {
        let library = dependencies.data.allPuzzles()
        let favoriteIDs = dependencies.data.favoriteIDs()
        // Newest favorites first: keep the set-membership filter, order by the
        // library is unstable, so sort by id for determinism.
        favorites = library
            .filter { favoriteIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func rowAccessibilityLabel(_ puzzle: Puzzle) -> String {
        String(
            format: NSLocalizedString("favorites.row_accessibility", comment: "Favorite row summary"),
            puzzle.id, puzzle.rating ?? 0
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
