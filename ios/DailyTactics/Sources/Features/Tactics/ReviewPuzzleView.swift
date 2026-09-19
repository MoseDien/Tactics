import SwiftUI
import PuzzleKit
import ChessCore

/// Single-puzzle replay from the favorites list.
struct ReviewPuzzleView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzle: Puzzle
    @State private var session: PuzzleSession?
    @State private var stepRevision = 0
    @State private var steppingForward = false
    /// Captured before stepBack drops it: the piece re-appears on `from`.
    @State private var lastUndoneMove: ChessMove?

    var body: some View {
        VStack(spacing: 14) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            if let session {
                ChessBoardView(position: session.board.pieces, selectedSquare: nil, hintMove: nil,
                               lastMove: session.lastMove, isFlipped: session.userColor == .black,
                               animation: boardAnimation(for: session),
                               onSelect: { _ in })
                .aspectRatio(1, contentMode: .fit)

                HStack {
                    Button { step(-1) } label: { Text("< \(String(localized: "review.previous_move"))") }
                        .disabled(!session.canStepBack)
                    Spacer()
                    Button { step(1) } label: { Text("\(String(localized: "review.next_move")) >") }
                        .disabled(!session.canStepForward)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
        .navigationTitle(String(localized: "review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(String(localized: "common.done")) { dismiss() } }
        .task { loadCurrent() }
    }

    // MARK: - Header

    private var header: some View {
        PuzzleHeaderView(puzzle: puzzle, playerColor: playerColor)
    }

    /// FEN side-to-move's opponent, as the live session derives it.
    private var playerColor: PieceColor {
        guard let side = puzzle.fen.split(separator: " ").dropFirst().first,
              side == "w" || side == "b"
        else { return .white }
        return side == "w" ? .black : .white
    }

    // MARK: - Replay animation

    /// Forward steps slide; back-steps revert-slide; loads render in place.
    private func boardAnimation(for session: PuzzleSession) -> BoardAnimation {
        var arrival: [Square: Square] = [:]
        var isSnapback = false
        if stepRevision > 0, !steppingForward, let undone = lastUndoneMove {
            arrival[undone.from] = undone.to
            isSnapback = true
        } else if stepRevision > 0, let move = session.lastMove, steppingForward {
            arrival[move.to] = move.from
            if let rook = session.castlingRookMove() {
                arrival[rook.to] = rook.from
            }
        }
        return BoardAnimation(
            arrival: arrival,
            boardGeneration: 0,
            moveRevision: stepRevision,
            isSnapback: isSnapback
        )
    }

    private func loadCurrent() {
        session = try? PuzzleSession(puzzle: puzzle)
        if session != nil { try? session?.stepForward() }
        stepRevision = 0
    }

    private func step(_ direction: Int) {
        guard var current = session else { return }
        steppingForward = direction > 0
        if direction < 0, current.canStepBack {
            lastUndoneMove = current.lastMove
            try? current.stepBack()
        } else {
            lastUndoneMove = nil
        }
        if direction > 0, current.canStepForward { try? current.stepForward() }
        session = current
        stepRevision += 1
    }
}
