import SwiftUI

struct AnalysisBoardAnimation: Equatable {
    var arrival: [Analysis.Square: Analysis.Square]
    var boardGeneration: Int
    var moveRevision: Int
    var isUndo: Bool
}

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
    let animation: AnalysisBoardAnimation
    let onSelect: (Analysis.Square) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)
    private static let darkSquare = Color(red: 0.71, green: 0.52, blue: 0.36)
    private static let lastMoveHighlight = Color(red: 0.76, green: 0.80, blue: 0.25).opacity(0.55)
    private static let selectedHighlight = Color(red: 0.88, green: 0.72, blue: 0.12).opacity(0.55)

    private var ranks: [Int] { isFlipped ? Array(0...7) : Array(stride(from: 7, through: 0, by: -1)) }
    private var files: [Int] { isFlipped ? Array(stride(from: 7, through: 0, by: -1)) : Array(0...7) }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSide = side / 8
            squares(squareSide: squareSide)
                .overlay {
                    pieceLayer(squareSide: squareSide, side: side)
                }
                .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func squares(squareSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(ranks, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(files, id: \.self) { file in
                        if let square = Analysis.Square(file: file, rank: rank) {
                            cell(for: square, squareSide: squareSide)
                        }
                    }
                }
            }
        }
    }

    private func cell(for square: Analysis.Square, squareSide: CGFloat) -> some View {
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

                if position[square] == nil, legalTargets.contains(square) {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: 13, height: 13)
                }

                coordinateLabels(for: square)
            }
            .frame(width: squareSide, height: squareSide)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(squareAccessibilityLabel(for: square))
    }

    private struct Placement: Identifiable {
        let id: String
        let piece: Analysis.Piece
        let square: Analysis.Square
    }

    private var placements: [Placement] {
        position.squares.enumerated().compactMap { index, piece in
            guard let piece, let square = Analysis.Square(index: index) else { return nil }
            return Placement(
                id: "\(piece.assetName)-\(square.notation)#\(animation.boardGeneration)",
                piece: piece,
                square: square
            )
        }
    }

    private func pieceLayer(squareSide: CGFloat, side: CGFloat) -> some View {
        ZStack {
            ForEach(placements) { placement in
                Image(placement.piece.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: squareSide * 0.88, height: squareSide * 0.88)
                    .frame(width: squareSide, height: squareSide)
                    .offset(offset(for: placement.square, squareSide: squareSide))
                    .transition(transition(for: placement, squareSide: squareSide))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(transactionAnimation, value: boardStamp)
    }

    private var boardStamp: String {
        "\(position.squares.compactMap { $0 }.count)-\(animation.boardGeneration)-\(animation.moveRevision)-\(animation.arrival.count)"
    }

    private var transactionAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return animation.arrival.isEmpty ? .easeOut(duration: 0.18) : .easeOut(duration: animation.isUndo ? 0.09 : 0.15)
    }

    private func transition(for placement: Placement, squareSide: CGFloat) -> AnyTransition {
        guard let origin = animation.arrival[placement.square], !reduceMotion else {
            return animation.arrival.isEmpty && !reduceMotion ? .opacity : .identity
        }
        let start = offset(for: origin, squareSide: squareSide)
        let end = offset(for: placement.square, squareSide: squareSide)
        return .asymmetric(
            insertion: .offset(CGSize(width: start.width - end.width, height: start.height - end.height)),
            removal: .identity
        )
    }

    private func offset(for square: Analysis.Square, squareSide: CGFloat) -> CGSize {
        let column = files.firstIndex(of: square.file) ?? square.file
        let row = ranks.firstIndex(of: square.rank) ?? (7 - square.rank)
        return CGSize(width: CGFloat(column) * squareSide, height: CGFloat(row) * squareSide)
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
