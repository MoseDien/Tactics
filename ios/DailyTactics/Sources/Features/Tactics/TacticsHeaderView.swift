import SwiftUI
import PuzzleKit
import ChessCore

/// The training board's header: the puzzle-progress caption over the shared
/// board header band; its accessory is the difficulty stars (tapping them
/// reveals the rating and play count).
struct TacticsHeaderView: View {
    let viewModel: TacticsHeaderViewModel
    @State private var showingPuzzleDetails = false

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: NSLocalizedString("tactics.puzzle_progress", comment: "Puzzle progress"), viewModel.puzzleNumber, viewModel.puzzleCount))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .lineLimit(1)

            BoardHeaderView(
                kingAsset: viewModel.playerColor == .white ? "wK" : "bK",
                title: viewModel.title,
                subtitle: viewModel.subtitle
            ) {
                difficultyStars
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Unhighlighted stars fade; tapping reveals rating and play count.
    private var difficultyStars: some View {
        Button {
            showingPuzzleDetails.toggle()
        } label: {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { level in
                        Image(systemName: level <= FavoritesViewModel.difficultyLevel(for: viewModel.rating) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(level <= FavoritesViewModel.difficultyLevel(for: viewModel.rating) ? Color.primary : Color.secondary.opacity(0.45))
                    }
                }
                if showingPuzzleDetails {
                    HStack(spacing: 8) {
                        if let rating = viewModel.rating {
                            Label("\(rating)", systemImage: "gauge.medium")
                        }
                        if let plays = viewModel.playCount {
                            Label(plays.formatted(), systemImage: "play.circle")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "tactics.puzzle_difficulty"))
        .accessibilityHint(String(localized: "tactics.puzzle_difficulty_hint"))
    }
}
