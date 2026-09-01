import SwiftUI
import PuzzleKit

/// A horizontal row of per-puzzle markers shown below the board. Shared by the
/// daily round so all result screens read identically:
///
/// - green check: solved correctly
/// - gray check: not yet attempted (initial state)
/// - soft-red cross: a wrong move was made
struct PuzzleResultRow: View {
    let outcomes: [PuzzleOutcome?]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(outcomes.indices, id: \.self) { index in
                marker(for: outcomes[index])
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func marker(for outcome: PuzzleOutcome?) -> some View {
        if outcome == .correct {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)
        } else if outcome == .wrong {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red.opacity(0.6))
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
