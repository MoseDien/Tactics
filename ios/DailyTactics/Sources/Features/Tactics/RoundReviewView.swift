import SwiftUI
import PuzzleKit
import ChessCore

/// Continuous review player for a completed round: step through each puzzle's
/// line, then move on to the next puzzle (looping at the end). Read-only —
/// no scoring, no repositories, no round tracker; the historical round is a
/// plain dataset by the time it reaches this view.
struct RoundReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzles: [Puzzle]
    let outcomes: [PuzzleOutcome?]

    @State private var puzzleIndex = 0
    @State private var session: PuzzleSession?
    /// Bumped on every in-line step so each replayed move gets its own
    /// animation transaction (forward and back alike).
    @State private var stepRevision = 0
    /// Bumped on every puzzle change so the new board fades in (same load
    /// semantics as the live screen).
    @State private var boardGeneration = 0
    /// Whether the pending step moves the line forward (the only direction
    /// that slides; back-steps snap).
    @State private var steppingForward = false

    var body: some View {
        VStack(spacing: 12) {
            header

            if let session {
                ChessBoardView(
                    position: session.board.pieces,
                    selectedSquare: nil,
                    hintMove: nil,
                    lastMove: session.lastMove,
                    isFlipped: session.userColor == .black,
                    animation: boardAnimation(for: session),
                    onSelect: { _ in }
                )
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 16)

                moveStepping(for: session)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(String(localized: "common.done")) { dismiss() } }
        .task(id: puzzleIndex) { loadCurrent() }
    }

    /// "Puzzle 2 of 5" plus the round's per-puzzle result row, marking where
    /// the player currently is.
    private var header: some View {
        VStack(spacing: 6) {
            Text(String(format: NSLocalizedString("history.puzzle_progress", comment: "Current puzzle within a reviewed round"), puzzleIndex + 1, puzzles.count))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                marker(at: puzzleIndex)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor.opacity(0.14)))
                HStack(spacing: 8) {
                    ForEach(outcomes.indices, id: \.self) { index in
                        marker(at: index)
                            .frame(width: 20, height: 20)
                            .opacity(index == puzzleIndex ? 1 : 0.45)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func marker(at index: Int) -> some View {
        if outcomes.indices.contains(index), outcomes[index] == .wrong {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.red.opacity(0.65))
        } else if outcomes.indices.contains(index), outcomes[index] == .correct {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dashed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// In-line stepping for the current puzzle, plus puzzle-to-puzzle
    /// navigation (looping after the last one).
    private func moveStepping(for session: PuzzleSession) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button { step(-1) } label: { Label(String(localized: "review.previous_move"), systemImage: "chevron.left") }
                    .disabled(!session.canStepBack)
                Spacer()
                Button { step(1) } label: { Label(String(localized: "review.next_move"), systemImage: "chevron.right") }
                    .disabled(!session.canStepForward)
            }
            .buttonStyle(.bordered)

            HStack {
                Button { advancePuzzle(-1) } label: { Label(String(localized: "review.prev_puzzle"), systemImage: "backward.end") }
                Spacer()
                Button { advancePuzzle(1) } label: { Label(String(localized: "review.next_puzzle"), systemImage: "forward.end") }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// The replay's animation input: forward steps slide the arriving piece in
    /// from its origin (the live screen's rule, castling rook included); a
    /// puzzle change fades the fresh board in; back-steps render in place.
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
            setupEnabled: true,
            boardGeneration: boardGeneration,
            moveRevision: stepRevision
        )
    }

    private func loadCurrent() {
        guard puzzles.indices.contains(puzzleIndex) else { return }
        session = try? PuzzleSession(puzzle: puzzles[puzzleIndex])
        if session != nil { try? session?.stepForward() }
        stepRevision = 0
        boardGeneration += 1
    }

    private func step(_ direction: Int) {
        guard var current = session else { return }
        steppingForward = direction > 0
        if direction < 0, current.canStepBack { try? current.stepBack() }
        if direction > 0, current.canStepForward { try? current.stepForward() }
        session = current
        stepRevision += 1
    }

    private func advancePuzzle(_ direction: Int) {
        guard !puzzles.isEmpty else { return }
        puzzleIndex = (puzzleIndex + direction + puzzles.count) % puzzles.count
    }
}
