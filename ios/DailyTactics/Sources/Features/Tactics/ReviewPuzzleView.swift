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
    /// Whether the pending step moves the line forward.
    @State private var steppingForward = false
    /// The move a back-step just removed (captured before the session drops
    /// it): its piece re-appears on `from`, having arrived from `to`.
    @State private var lastUndoneMove: ChessMove?

    var body: some View {
        VStack(spacing: 14) {
            header

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
        .padding()
        .navigationTitle(String(localized: "review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(String(localized: "common.done")) { dismiss() } }
        .task { loadCurrent() }
    }

    // MARK: - Header

    /// The puzzle's own card, mirroring `RoundReviewView`'s: side to move
    /// (the player's king), id and subtitle on the left; rating, difficulty
    /// stars and the leading theme on the right.
    private var header: some View {
        HStack(spacing: 14) {
            HStack {
                Image(playerColor == .white ? "wK" : "bK")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.94, green: 0.85, blue: 0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(puzzle.id)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                    Text(String(localized: playerColor == .white ? "tactics.find_best_white" : "tactics.find_best_black"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                if let rating = puzzle.rating {
                    Text("\(rating)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { level in
                        Image(systemName: level <= FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(level <= FavoritesViewModel.difficultyLevel(for: puzzle.rating) ? Color.primary : Color.secondary.opacity(0.45))
                    }
                }
                if let theme = puzzle.themes.first {
                    Text(themeName(theme))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// The side the puzzle asks the player to move for (the FEN side-to-move's
    /// opponent — same rule as the live session).
    private var playerColor: PieceColor {
        guard let side = puzzle.fen.split(separator: " ").dropFirst().first,
              side == "w" || side == "b"
        else { return .white }
        return side == "w" ? .black : .white
    }

    private func themeName(_ theme: PuzzleTheme) -> String {
        NSLocalizedString("theme.\(theme.rawValue)", comment: "Puzzle theme name")
    }

    // MARK: - Replay animation

    /// The replay's animation input: forward steps slide the arriving piece
    /// in from its origin (live play's rule); back-steps slide the undone
    /// move's piece home — the revert runs one-third faster. The initial
    /// load renders in place (a ready position).
    private func boardAnimation(for session: PuzzleSession) -> BoardAnimation {
        var arrival: [Square: Square] = [:]
        var isSnapback = false
        if stepRevision > 0, !steppingForward, let undone = lastUndoneMove {
            // The move a back-step just removed: its piece re-appears on
            // `from`, having slid home from `to` — one-third faster.
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
