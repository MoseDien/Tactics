import SwiftUI
import PuzzleKit

/// Green check = correct, gray disc = current puzzle, gray check = not yet
/// attempted, soft-red cross = wrong.
struct PuzzleResultRow: View {
    let outcomes: [PuzzleOutcome?]
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
        symbol(for: outcome)
            .frame(width: 22, height: 22)
            .background {
                if isCurrent {
                    Circle().fill(Color.secondary.opacity(0.28))
                }
            }
    }

    @ViewBuilder
    private func symbol(for outcome: PuzzleOutcome?) -> some View {
        switch outcome {
        case .correct:
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)
        case .wrong:
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red.opacity(0.6))
        case nil:
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
