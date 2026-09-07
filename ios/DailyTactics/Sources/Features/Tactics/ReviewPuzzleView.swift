import SwiftUI
import PuzzleKit
import ChessCore

/// Review for one completed puzzle: step through its line move by move.
/// Used from the favorites list; round review has its own continuous player
/// (`RoundReviewView`).
struct ReviewPuzzleView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var session: PuzzleSession?
    /// Bumped on every step so the board sees each replayed move as a fresh
    /// animation transaction (forward and back alike).
    @State private var stepRevision = 0

    var body: some View {
        VStack(spacing: 14) {
            Text(String(localized: "review.label"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let session {
                ChessBoardView(position: session.board.pieces, selectedSquare: nil, hintMove: nil,
                               lastMove: session.lastMove, isFlipped: session.userColor == .black,
                               animation: boardAnimation(for: session),
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

    /// The replay's animation input: stepping forward slides the arriving
    /// piece in from its origin (same rule as live play); the initial load
    /// and stepping back render in place — a load presents a ready position,
    /// and a taken-back move has no arrival to slide from.
    private func boardAnimation(for session: PuzzleSession) -> BoardAnimation {
        var arrival: [Square: Square] = [:]
        if stepRevision > 0, let move = session.lastMove, steppingForward {
            arrival[move.to] = move.from
            if let rook = session.castlingRookMove() {
                arrival[rook.to] = rook.from
            }
        }
        return BoardAnimation(
            arrival: arrival,
            movesEnabled: true,
            setupEnabled: false,
            boardGeneration: 0,
            moveRevision: stepRevision
        )
    }

    /// Whether the pending step moves the line forward (the only direction
    /// that plays a slide; back-steps snap).
    @State private var steppingForward = false

    private func loadCurrent() {
        session = try? PuzzleSession(puzzle: puzzle)
        if session != nil { try? session?.stepForward() }
        stepRevision = 0
    }

    private func step(_ direction: Int) {
        guard var current = session else { return }
        steppingForward = direction > 0
        if direction < 0, current.canStepBack { try? current.stepBack() }
        if direction > 0, current.canStepForward { try? current.stepForward() }
        session = current
        stepRevision += 1
    }
}
