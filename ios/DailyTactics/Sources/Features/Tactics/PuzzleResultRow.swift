import SwiftUI
import PuzzleKit

/// A horizontal row of per-puzzle markers shown below the board. Shared by the
/// daily round so all result screens read identically:
///
/// - green check: solved correctly
/// - gray check on a gray disc: the puzzle currently being played
/// - gray check: not yet attempted
/// - soft-red cross: a wrong move was made
struct PuzzleResultRow: View {
    let outcomes: [PuzzleOutcome?]
    /// The puzzle currently on the board, if any. It renders as a gray disc
    /// with a white check so the player can see where they are in the round.
    var currentIndex: Int? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(outcomes.indices, id: \.self) { index in
                marker(for: outcomes[index], isCurrent: index == currentIndex)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func marker(for outcome: PuzzleOutcome?, isCurrent: Bool) -> some View {
        if outcome == .correct {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)
        } else if outcome == .wrong {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red.opacity(0.6))
        } else if isCurrent {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.45)))
        } else {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        let resolved = outcomes.compactMap { $0 }
        let correct = resolved.filter { $0 == .correct }.count
        let wrong = resolved.filter { $0 == .wrong }.count
        return String(
            format: NSLocalizedString("results.summary", comment: "Accessibility summary of round results"),
            correct, wrong
        )
    }
}
