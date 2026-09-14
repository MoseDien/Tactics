import SwiftUI
import PuzzleKit
import TacticsData

/// The favorited puzzles, newest favorite first. Pure layout; state and row
/// derivation live in `FavoritesViewModel`.
struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: FavoritesViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    list(for: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "settings.favorites"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(String(localized: "common.done")) { dismiss() } }
            .task {
                if viewModel == nil {
                    let built = FavoritesViewModel(dependencies: dependencies)
                    built.reload()
                    viewModel = built
                }
            }
        }
    }

    @ViewBuilder
    private func list(for model: FavoritesViewModel) -> some View {
        List(model.entries, id: \.puzzle.id) { entry in
            NavigationLink {
                ReviewPuzzleView(puzzle: entry.puzzle)
            } label: {
                favoriteRow(entry, model: model)
            }
        }
        .overlay { if model.entries.isEmpty { emptyState } }
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
    private func favoriteRow(
        _ entry: (puzzle: Puzzle, favoritedAt: Date?),
        model: FavoritesViewModel
    ) -> some View {
        let puzzle = entry.puzzle
        return HStack(spacing: 12) {
            VStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { level in
                    Image(systemName: level < FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? "star.fill" : "star")
                        .font(.system(size: 7))
                        .foregroundStyle(level < FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? Color.primary : Color.secondary.opacity(0.4))
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
                        NSLocalizedString(model.playerColorKey(for: puzzle), comment: "Side the player holds"),
                        systemImage: model.playerColorSymbol(for: puzzle)
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
                Text(model.themeName(theme))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.rowAccessibilityLabel(for: entry))
    }
}
