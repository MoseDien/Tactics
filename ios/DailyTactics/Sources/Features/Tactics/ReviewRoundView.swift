import SwiftUI

struct ReviewRoundView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var session: PuzzleSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("REVIEW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                if let session {
                    ChessBoardView(position: session.board.pieces, selectedSquare: nil, hintMove: nil,
                                   lastMove: session.lastMove, isFlipped: session.userColor == .black,
                                   onSelect: { _ in })
                    .aspectRatio(1, contentMode: .fit)
                    HStack {
                        Button { step(-1) } label: { Label("Previous move", systemImage: "chevron.left") }
                            .disabled(!session.canStepBack)
                        Spacer()
                        Button { step(1) } label: { Label("Next move", systemImage: "chevron.right") }
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
    @Environment(\.modelContext) private var modelContext
    @State private var rounds: [RoundHistory] = []
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
            .overlay { if rounds.isEmpty { ContentUnavailableView("No history yet", systemImage: "clock") } }
            .navigationTitle("History")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                let store = PuzzleProgressStore(context: modelContext)
                rounds = store.history()
                puzzleLookup = Dictionary(uniqueKeysWithValues: store.allPuzzles().map { ($0.id, $0) })
            }
        }
    }
}

private struct RoundHistoryDetail: View {
    let round: RoundHistory
    let puzzleLookup: [String: Puzzle]

    var body: some View {
        List(Array(round.puzzleIDs.enumerated()), id: \.offset) { index, id in
            if let puzzle = puzzleLookup[id] {
                NavigationLink {
                    ReviewRoundView(puzzle: puzzle)
                } label: {
                    HStack {
                        Text("Puzzle \(index + 1)")
                        Spacer()
                        Text(round.outcomes.indices.contains(index) && round.outcomes[index] == "correct" ? "✓" : "×")
                            .foregroundStyle(round.outcomes.indices.contains(index) && round.outcomes[index] == "correct" ? .green : .secondary)
                    }
                }
            }
        }
        .navigationTitle("Round Review")
    }
}
