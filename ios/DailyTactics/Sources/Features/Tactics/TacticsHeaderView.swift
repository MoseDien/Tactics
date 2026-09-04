import SwiftUI
import PuzzleKit
import ChessCore

/// The board header: puzzle progress, the player's side, and the difficulty
/// stars (tapping them reveals the rating and play count).
struct TacticsHeaderView: View {
    let viewModel: TacticsViewModel
    @State private var showingPuzzleDetails = false

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: NSLocalizedString("tactics.puzzle_progress", comment: "Puzzle progress"), viewModel.puzzleNumber, viewModel.puzzleCount))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            HStack(spacing: 14) {
                HStack {
                    Image(viewModel.playerColor == .white ? "wK" : "bK")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .frame(width: 54, height: 54)
                        .background(Color(red: 0.94, green: 0.85, blue: 0.70))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.headerTitle)
                        Text(viewModel.headerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showingPuzzleDetails.toggle()
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { level in
                                Image(systemName: level <= difficultyLevel(for: viewModel.currentPuzzleRating) ? "star.fill" : "star")
                                    .foregroundStyle(level <= difficultyLevel(for: viewModel.currentPuzzleRating) ? Color.primary : Color.secondary.opacity(0.45))
                            }
                        }
                        if showingPuzzleDetails {
                            HStack(spacing: 8) {
                                if let rating = viewModel.currentPuzzleRating {
                                    Label("\(rating)", systemImage: "gauge.medium")
                                }
                                if let plays = viewModel.currentPuzzlePlayCount {
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
            .padding(8)
            .background(Color(.secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        }
        .frame(maxWidth: .infinity)
    }

    private func difficultyLevel(for rating: Int?) -> Int {
        guard let rating else { return 3 }
        return min(5, max(1, (rating - 800) / 240 + 1))
    }
}
