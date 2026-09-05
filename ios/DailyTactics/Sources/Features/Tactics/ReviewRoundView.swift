import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

/// History browser: rounds grouped into calendar weeks (newest first), each
/// row showing the batch's results at a glance. Tapping a round opens the
/// continuous batch review player.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var weeks: [HistoryGrouper.Week] = []
    @State private var puzzleLookup: [String: Puzzle] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(weeks) { week in
                    Section {
                        ForEach(week.rounds) { round in
                            NavigationLink {
                                BatchReviewView(
                                    puzzles: round.puzzleIDs.compactMap { puzzleLookup[$0] },
                                    outcomes: round.outcomes
                                )
                            } label: {
                                roundRow(round)
                            }
                        }
                    } header: {
                        weekHeader(week)
                    }
                }
            }
            .overlay { if weeks.isEmpty { ContentUnavailableView(String(localized: "history.empty"), systemImage: "clock") } }
            .navigationTitle(String(localized: "settings.history"))
            .toolbar { Button(String(localized: "common.done")) { dismiss() } }
            .task {
                let library = dependencies.data.allPuzzles()
                weeks = HistoryGrouper.weeks(from: dependencies.data.history())
                puzzleLookup = BatchLookup.puzzles(withIDs: library.map(\.id), in: library)
                    .reduce(into: [:]) { lookup, puzzle in lookup[puzzle.id] = puzzle }
            }
        }
    }

    /// One batch: completion time, the per-puzzle result row, and a solved
    /// ratio capsule.
    private func roundRow(_ round: RoundSummary) -> some View {
        HStack(spacing: 12) {
            Text(round.completedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            HStack(spacing: 7) {
                ForEach(round.outcomes.indices, id: \.self) { index in
                    outcomeMark(round.outcomes[index])
                        .font(.footnote.weight(.bold))
                        .frame(width: 17, height: 17)
                }
            }

            Spacer(minLength: 4)

            let solved = round.outcomes.filter { $0 == .correct }.count
            Text("\(solved)/\(round.puzzleIDs.count)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(solved == round.puzzleIDs.count ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(solved == round.puzzleIDs.count
                        ? Color.green.opacity(0.13)
                        : Color.secondary.opacity(0.12))
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(round))
    }

    @ViewBuilder
    private func outcomeMark(_ outcome: PuzzleOutcome?) -> some View {
        switch outcome {
        case .correct:
            Image(systemName: "checkmark").foregroundStyle(.green)
        case .wrong:
            Image(systemName: "xmark").foregroundStyle(.red.opacity(0.65))
        case nil:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    /// Week title plus a totals line (puzzles and correct/wrong counts).
    private func weekHeader(_ week: HistoryGrouper.Week) -> some View {
        let s = week.summary
        return HStack {
            Text(week.name)
            Spacer()
            Text("\(s.puzzles) · \(s.correct)✓ \(s.wrong)×")
                .foregroundStyle(.secondary)
                .font(.footnote.monospacedDigit())
        }
    }

    private func rowAccessibilityLabel(_ round: RoundSummary) -> String {
        let solved = round.outcomes.filter { $0 == .correct }.count
        return String(
            format: NSLocalizedString("history.row_accessibility", comment: "History row summary"),
            round.completedAt.formatted(date: .abbreviated, time: .shortened),
            solved, round.puzzleIDs.count
        )
    }
}
