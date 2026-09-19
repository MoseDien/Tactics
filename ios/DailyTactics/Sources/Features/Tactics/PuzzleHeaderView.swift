import SwiftUI
import PuzzleKit
import ChessCore

/// One puzzle's board header: id and side at the left; rating, difficulty
/// stars, and theme at the right. Shared by the single-puzzle and
/// round-review sheets.
struct PuzzleHeaderView: View {
    let puzzle: Puzzle
    let playerColor: PieceColor

    var body: some View {
        BoardHeaderView(
            kingAsset: playerColor == .white ? "wK" : "bK",
            title: "#\(puzzle.id)",
            subtitle: String(localized: playerColor == .white ? "tactics.find_best_white" : "tactics.find_best_black")
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                if let rating = puzzle.rating {
                    Text("\(rating)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { level in
                        Image(systemName: level <= FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(level <= FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? Color.primary : Color.secondary.opacity(0.45))
                    }
                }
                if let theme = puzzle.themes.first {
                    Text(themeName(theme))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
        }
    }

    private func themeName(_ theme: PuzzleTheme) -> String {
        NSLocalizedString("theme.\(theme.rawValue)", comment: "Puzzle theme name")
    }
}
