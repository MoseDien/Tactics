import SwiftUI

/// Tap-to-move grid for the analysis board. Visual constants mirror the
/// training board's literals (kept independent of its code): warm square
/// palette, edge coordinates, in-cell pieces — no slide animation here.
/// Cells self-size as squares, so the grid takes exactly its width in
/// height and never starves siblings in a stack.
struct AnalysisBoardGridView: View {
    let position: Analysis.Position
    let selectedSquare: Analysis.Square?
    let legalTargets: Set<Analysis.Square>
    let lastMove: Analysis.Move?
    let isFlipped: Bool
    let onSelect: (Analysis.Square) -> Void

    private static let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)
    private static let darkSquare = Color(red: 0.71, green: 0.52, blue: 0.36)
    private static let lastMoveHighlight = Color(red: 0.76, green: 0.80, blue: 0.25).opacity(0.55)
    private static let selectedHighlight = Color(red: 0.88, green: 0.72, blue: 0.12).opacity(0.55)

    private var ranks: [Int] { isFlipped ? Array(0...7) : Array(stride(from: 7, through: 0, by: -1)) }
    private var files: [Int] { isFlipped ? Array(stride(from: 7, through: 0, by: -1)) : Array(0...7) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ranks, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(files, id: \.self) { file in
                        if let square = Analysis.Square(file: file, rank: rank) {
                            cell(for: square)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cell(for square: Analysis.Square) -> some View {
        return Button {
            onSelect(square)
        } label: {
            ZStack {
                ((square.file + square.rank).isMultiple(of: 2) ? Self.darkSquare : Self.lightSquare)

                if isMoveEndpoint(square) {
                    Self.lastMoveHighlight
                }
                if square == selectedSquare {
                    Self.selectedHighlight
                }

                if let piece = position[square] {
                    Image(piece.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if legalTargets.contains(square) {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: 13, height: 13)
                }

                coordinateLabels(for: square)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(squareAccessibilityLabel(for: square))
    }

    private func isMoveEndpoint(_ square: Analysis.Square) -> Bool {
        lastMove.map { $0.from == square || $0.to == square } ?? false
    }

    /// Same geometry as the training board: rank digits lead the rightmost
    /// file, file letters lead the bottom rank, opposite-square ink.
    @ViewBuilder
    private func coordinateLabels(for square: Analysis.Square) -> some View {
        VStack {
            HStack {
                if square.file == files.last {
                    Text("\(square.rank + 1)")
                }
                Spacer()
            }
            Spacer()
            HStack {
                if square.rank == ranks.last {
                    Text(String(Character(UnicodeScalar(UInt8(square.file + 97)))))
                }
                Spacer()
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle((square.file + square.rank).isMultiple(of: 2) ? Self.lightSquare : Self.darkSquare)
        .padding(4)
    }

    private func squareAccessibilityLabel(for square: Analysis.Square) -> String {
        if let piece = position[square] {
            return String(
                format: NSLocalizedString("board.square_occupied", comment: "Occupied square accessibility"),
                NSLocalizedString(piece.color == .white ? "piece.white.name" : "piece.black.name", comment: ""),
                NSLocalizedString("piece.\(piece.kind.rawValue).name", comment: ""),
                square.notation
            )
        }
        return String(
            format: NSLocalizedString("board.square_empty", comment: "Empty square accessibility"),
            square.notation
        )
    }
}
