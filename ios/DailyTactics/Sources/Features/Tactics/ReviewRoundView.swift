import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

/// Review for one completed puzzle. Batch review remains handled by
/// `TacticsView(mode: .reviewBatch)`.
struct ReviewPuzzleView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var session: PuzzleSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(String(localized: "review.label"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                if let session {
                    ChessBoardView(position: session.board.pieces, selectedSquare: nil, hintMove: nil,
                                   lastMove: session.lastMove, isFlipped: session.userColor == .black,
                                   onSelect: { _ in })
                    .aspectRatio(1, contentMode: .fit)
                    HStack {
                        Button { step(-1) } label: { Label(String(localized: "review.previous_move"), systemImage: "chevron.left") }
                            .disabled(!session.canStepBack)
                        Spacer()
                        Button { step(1) } label: { Label(String(localized: "review.next_move"), systemImage: "chevron.right") }
                            .disabled(!session.canStepForward)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "review.title"))
            .toolbar { Button(String(localized: "common.done")) { dismiss() } }
            .task { loadCurrent() }
        }
    }

    private func loadCurrent() {
        session = try? PuzzleSession(puzzle: puzzle)
        if session != nil { try? session?.stepForward() }
    }

    private func step(_ direction: Int) {
        guard var current = session else { return }
        if direction < 0, current.canStepBack { try? current.stepBack() }
        if direction > 0, current.canStepForward { try? current.stepForward() }
        session = current
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rounds: [RoundSummary] = []
    @State private var puzzleLookup: [String: Puzzle] = [:]

    var body: some View {
        NavigationStack {
            List(rounds) { round in
                NavigationLink {
                    RoundHistoryDetail(round: round, puzzleLookup: puzzleLookup)
                } label: {
                    VStack(alignment: .leading) {
                        Text(round.completedAt, style: .date)
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("history.puzzles_count", comment: "Number of puzzles in a history round"),
                            round.puzzleIDs.count
                        ))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if rounds.isEmpty { ContentUnavailableView(String(localized: "history.empty"), systemImage: "clock") } }
            .navigationTitle(String(localized: "settings.history"))
            .toolbar { Button(String(localized: "common.done")) { dismiss() } }
            .task {
                let store = SwiftDataRepositories(inMemory: false)
                rounds = store.history()
                // First occurrence wins so a duplicated library id can't trap.
                var lookup: [String: Puzzle] = [:]
                for puzzle in store.allPuzzles() where lookup[puzzle.id] == nil {
                    lookup[puzzle.id] = puzzle
                }
                puzzleLookup = lookup
            }
        }
    }
}

private struct RoundHistoryDetail: View {
    let round: RoundSummary
    let puzzleLookup: [String: Puzzle]

    var body: some View {
        List(Array(round.puzzleIDs.enumerated()), id: \.offset) { index, id in
            if let puzzle = puzzleLookup[id] {
                NavigationLink {
                    ReviewPuzzleView(puzzle: puzzle)
                } label: {
                    HStack {
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("history.puzzle", comment: "Puzzle index in a history round"),
                            "\(index + 1)"
                        ))
                        Spacer()
                        Text(round.outcomes.indices.contains(index) && round.outcomes[index] == .correct ? "✓" : "×")
                            .foregroundStyle(round.outcomes.indices.contains(index) && round.outcomes[index] == .correct ? .green : .secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "history.round_review"))
    }
}
