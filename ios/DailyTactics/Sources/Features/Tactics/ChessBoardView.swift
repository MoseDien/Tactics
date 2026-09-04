import SwiftUI
import ChessCore
import TacticsData

struct ChessBoardView: View {
    let position: [Square: Piece]
    let selectedSquare: Square?
    let hintMove: ChessMove?
    let lastMove: ChessMove?
    let isFlipped: Bool
    /// For each square that gained a piece in this render, the square that
    /// piece visually arrived from (the view model derives it — committed
    /// moves, wrong-move preview, snap-back, castling rook). Empty for puzzle
    /// loads: the board presents a ready position.
    var animatedArrival: [Square: Square] = [:]
    /// Whether pieces slide between squares. Off (debug toggle or Reduce
    /// Motion) renders every position change instantly.
    var movesAnimated: Bool = true
    let onSelect: (Square) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)
    private let darkSquare = Color(red: 0.71, green: 0.52, blue: 0.36)
    private let moveHighlight = Color(red: 0.76, green: 0.80, blue: 0.25)
    private let selectedHighlight = Color(red: 0.65, green: 0.69, blue: 0.10)

    /// Piece-travel animation: ease-out (non-linear, no overshoot, starts
    /// moving immediately — an ease-in start reads as a stall at the origin).
    private let moveAnimation: Animation = .easeOut(duration: 0.18)

    /// Ranks rendered top-to-bottom and files rendered left-to-right for the
    /// current perspective. The logical `Square` for each cell is unchanged, so
    /// move matching, highlights and taps all keep working when flipped.
    private var ranks: [Int] { isFlipped ? Array(0..<8) : Array((0..<8).reversed()) }
    private var files: [Int] { isFlipped ? Array(0..<8).reversed() : Array(0..<8) }
    private var bottomRank: Int { isFlipped ? 7 : 0 }
    private var rightmostFile: Int { isFlipped ? 0 : 7 }

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
    }

    // MARK: - Square layer (colors, highlights, coordinates — no pieces)

    private func squares(squareSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(ranks, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(files, id: \.self) { file in
                        // file/rank come from bounded 0..<8 loops.
                        squareCell(Square(file: file, rank: rank)!, squareSide: squareSide)
                    }
                }
            }
        }
    }

    private func squareCell(_ square: Square, squareSide: CGFloat) -> some View {
        Button {
            onSelect(square)
        } label: {
            ZStack {
                ((square.file + square.rank).isMultiple(of: 2) ? darkSquare : lightSquare)

                if hintMove?.from == square || hintMove?.to == square {
                    Color.green.opacity(0.42)
                }

                if lastMove?.from == square || lastMove?.to == square {
                    moveHighlight.opacity(0.82)
                }

                if selectedSquare == square {
                    selectedHighlight.opacity(0.88)
                }

                if hintMove?.to == square {
                    Circle()
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: squareSide * 0.84, height: squareSide * 0.84)
                }

                coordinateLabels(for: square)
            }
            .frame(width: squareSide, height: squareSide)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: square))
    }

    // MARK: - Piece layer

    /// One view per piece, offset-positioned. A move changes a piece's id
    /// (piece + square), so SwiftUI treats it as remove-at-origin +
    /// insert-at-destination; the insertion transition slides the arriving
    /// piece in from the square `animatedArrival` names. Removals are identity
    /// (captured pieces vanish; a stale slide-away would look wrong).
    private func pieceLayer(squareSide: CGFloat, side: CGFloat) -> some View {
        ZStack {
            ForEach(piecePlacements, id: \.id) { placement in
                Image(placement.piece.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: squareSide * 0.88, height: squareSide * 0.88)
                    .frame(width: squareSide, height: squareSide)
                    .offset(offset(for: placement.square, squareSide: squareSide))
                    .transition(arrivalTransition(for: placement, squareSide: squareSide))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .allowsHitTesting(false)
        // The single animation declaration: a `position` change plays each
        // arrival's slide through the transaction this modifier animates. An
        // empty arrival map means no move is attached to this change — a
        // puzzle load — and the transaction itself must not animate either:
        // pieces carried over from the previous puzzle (same id, same square)
        // are persistent views whose offsets would otherwise interpolate,
        // flying across the board when the perspective flips. Board flips
        // alone don't change `position`; Reduce Motion renders instantly.
        .animation(
            (slidesEnabled && !animatedArrival.isEmpty) ? moveAnimation : nil,
            value: position
        )
    }

    private var slidesEnabled: Bool {
        !reduceMotion && movesAnimated
    }

    /// Pieces sorted by square notation for a stable z-order (dictionary
    /// iteration order would reshuffle the layering every move).
    private var piecePlacements: [(id: String, piece: Piece, square: Square)] {
        position
            .sorted { $0.key.notation < $1.key.notation }
            .map { ($0.value.assetName + $0.key.notation, $0.value, $0.key) }
    }

    /// An arriving piece slides in from its origin square; everything else
    /// (loads, captures, selections) appears in place.
    private func arrivalTransition(
        for placement: (id: String, piece: Piece, square: Square),
        squareSide: CGFloat
    ) -> AnyTransition {
        guard slidesEnabled, let origin = animatedArrival[placement.square] else {
            return .identity
        }
        let from = offset(for: origin, squareSide: squareSide)
        let to = offset(for: placement.square, squareSide: squareSide)
        return .asymmetric(
            insertion: .offset(CGSize(width: from.width - to.width, height: from.height - to.height)),
            removal: .identity
        )
    }

    /// Top-left-origin offset for a square under the current perspective.
    private func offset(for square: Square, squareSide: CGFloat) -> CGSize {
        let column = files.firstIndex(of: square.file) ?? square.file
        let row = ranks.firstIndex(of: square.rank) ?? (7 - square.rank)
        return CGSize(width: CGFloat(column) * squareSide, height: CGFloat(row) * squareSide)
    }

    @ViewBuilder
    private func coordinateLabels(for square: Square) -> some View {
        VStack {
            HStack {
                if square.file == rightmostFile {
                    Text("\(square.rank + 1)")
                }
                Spacer()
            }
            Spacer()
            HStack {
                if square.rank == bottomRank {
                    Text(square.notation.prefix(1))
                }
                Spacer()
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle((square.file + square.rank).isMultiple(of: 2) ? lightSquare : darkSquare)
        .padding(4)
    }

    private func accessibilityLabel(for square: Square) -> String {
        guard let piece = position[square] else {
            let template = NSLocalizedString("board.square_empty", comment: "Accessibility label for an empty square")
            return String(format: template, square.notation)
        }
        let colorName = NSLocalizedString("piece.\(piece.color.rawValue).name", comment: "Piece color name")
        let kindName = NSLocalizedString("piece.\(piece.kind.rawValue).name", comment: "Piece kind name")
        let template = NSLocalizedString("board.square_occupied", comment: "Accessibility label for an occupied square")
        return String(format: template, colorName, kindName, square.notation)
    }
}
