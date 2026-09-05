import SwiftUI
import PuzzleKit
import ChessCore

/// Review for one completed puzzle: step through its line move by move.
/// Used from the favorites list; batch review has its own continuous player
/// (`BatchReviewView`).
struct ReviewPuzzleView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var session: PuzzleSession?

    var body: some View {
        VStack(spacing: 14) {
            Text(String(localized: "review.label"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let session {
                ChessBoardView(position: session.board.pieces, selectedSquare: nil, hintMove: nil,
                               lastMove: session.lastMove, isFlipped: session.userColor == .black,
                               animation: .passthrough,
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(String(localized: "common.done")) { dismiss() } }
        .task { loadCurrent() }
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
