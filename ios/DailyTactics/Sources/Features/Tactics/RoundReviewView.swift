import SwiftUI
import PuzzleKit
import ChessCore

/// Continuous read-only replay of a completed round: step through each line,
/// then the next puzzle (looping). The round arrives as a plain dataset.
struct RoundReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let puzzles: [Puzzle]
    let outcomes: [PuzzleOutcome?]

    @State private var puzzleIndex = 0
    @State private var session: PuzzleSession?
    @State private var stepRevision = 0
    @State private var boardGeneration = 0
    @State private var steppingForward = false
    /// Captured before stepBack drops it: the piece re-appears on `from`.
    @State private var lastUndoneMove: ChessMove?

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

                controls(for: session)
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text(String(format: NSLocalizedString("tactics.puzzle_progress", comment: "Puzzle progress"), puzzleIndex + 1, puzzles.count))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .lineLimit(1)

            PuzzleResultRow(outcomes: outcomes, currentIndex: puzzleIndex)

            if let puzzle = currentPuzzle {
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
                .padding(.horizontal, 4)
            }
        }
        .padding(.top, 8)
    }

    private var currentPuzzle: Puzzle? {
        puzzles.indices.contains(puzzleIndex) ? puzzles[puzzleIndex] : nil
    }

    /// FEN side-to-move's opponent, as the live session derives it.
    private var playerColor: PieceColor {
        guard let puzzle = currentPuzzle,
              let side = puzzle.fen.split(separator: " ").dropFirst().first,
              side == "w" || side == "b"
        else { return .white }
        return side == "w" ? .black : .white
    }

    private func themeName(_ theme: PuzzleTheme) -> String {
        NSLocalizedString("theme.\(theme.rawValue)", comment: "Puzzle theme name")
    }

    // MARK: - Controls

    /// Rows sit apart so step-move and step-puzzle can't be mis-tapped.
    private func controls(for session: PuzzleSession) -> some View {
        VStack(spacing: 22) {
            HStack {
                Button { step(-1) } label: { Text("< \(String(localized: "review.previous_move"))") }
                    .disabled(!session.canStepBack)
                Spacer()
                Button { step(1) } label: { Text("\(String(localized: "review.next_move")) >") }
                    .disabled(!session.canStepForward)
            }
            .buttonStyle(.bordered)

            HStack {
                Button { advancePuzzle(-1) } label: { Text("< \(String(localized: "review.prev_puzzle"))") }
                Spacer()
                Button { advancePuzzle(1) } label: { Text("\(String(localized: "review.next_puzzle")) >") }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Replay animation

    /// Forward steps slide; back-steps revert-slide; loads fade in.
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

    private func advancePuzzle(_ direction: Int) {
        guard !puzzles.isEmpty else { return }
        puzzleIndex = (puzzleIndex + direction + puzzles.count) % puzzles.count
    }
}
