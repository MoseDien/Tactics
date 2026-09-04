import SwiftUI
import ChessCore
import TacticsData

struct ChessBoardView: View {
    let position: [Square: Piece]
    let selectedSquare: Square?
    let hintMove: ChessMove?
    let lastMove: ChessMove?
    let isFlipped: Bool
    /// A move being demonstrated but not committed (the wrong-move preview).
    /// Its arriving piece slides in like a real move; when the preview clears,
    /// the piece slides back to its origin.
    var previewMove: ChessMove? = nil
    /// The just-cleared preview move, supplied in the same render that reverts
    /// the position, so the returning piece slides back instead of teleporting.
    var snapbackMove: ChessMove? = nil
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
    /// insert-at-destination; the insertion transition makes the arriving
    /// piece slide in from its origin square instead of popping in.
    private func pieceLayer(squareSide: CGFloat, side: CGFloat) -> some View {
        ZStack {
            ForEach(piecePlacements, id: \.id) { placement in
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
        // The single animation declaration: a `position` change gives the
        // structural insertions/removals an animated transaction, which plays
        // each arrival's slide. Board flips (`position` unchanged) and Reduce
        // Motion render instantly.
        .animation(reduceMotion ? nil : moveAnimation, value: position)
    }

    /// Pieces sorted by square notation for a stable z-order (dictionary
    /// iteration order would reshuffle the layering every move).
    private var piecePlacements: [(id: String, piece: Piece, square: Square)] {
        position
            .sorted { $0.key.notation < $1.key.notation }
            .map { ($0.value.assetName + $0.key.notation, $0.value, $0.key) }
    }

    /// The move whose arriving piece `placement` renders, if any. Order
    /// matters: the preview/snapback (what is being demonstrated right now)
    /// outranks `lastMove`, otherwise a wrong move landing on the opponent's
    /// just-vacated square would fly in from the *opponent's* origin.
    /// A snapback is the preview move reversed: the piece re-lands on
    /// `move.from`, flying back from `move.to`.
    private func arrivalMove(for placement: (id: String, piece: Piece, square: Square)) -> ChessMove? {
        if let snap = snapbackMove, snap.from == placement.square {
            return ChessMove(from: snap.to, to: snap.from)
        }
        return [previewMove, lastMove, castlingRookMove()]
            .compactMap { $0 }
            .first { $0.to == placement.square }
    }

    /// Castling also relocates a rook; derive its move from the king's
    /// two-file jump so the rook slides too. Only a king ever moves two files
    /// sideways, so the guard has no false positives.
    private func castlingRookMove() -> ChessMove? {
        guard let move = lastMove,
              position[move.to]?.kind == .king,
              abs(move.to.file - move.from.file) == 2
        else { return nil }
        let rookFrom: Int
        let rookTo: Int
        if move.to.file > move.from.file {
            rookFrom = 7; rookTo = 5
        } else {
            rookFrom = 0; rookTo = 3
        }
        // rookFrom/rookTo/rank are bounded 0..<8, so the failable inits succeed.
        guard position[Square(file: rookTo, rank: move.to.rank)!]?.kind == .rook else { return nil }
        return ChessMove(
            from: Square(file: rookFrom, rank: move.to.rank)!,
            to: Square(file: rookTo, rank: move.to.rank)!
        )
    }

    /// Sliding arrivals in, identity removals out: a captured piece must not
    /// slide away with the previous move's stale offset configuration.
    private func transition(
        for placement: (id: String, piece: Piece, square: Square),
        squareSide: CGFloat
    ) -> AnyTransition {
        guard !reduceMotion, let arrival = arrivalMove(for: placement) else { return .identity }
        return .asymmetric(
            insertion: .offset(travelDelta(from: arrival.from, to: arrival.to, squareSide: squareSide)),
            removal: .identity
        )
    }

    /// Origin-offset minus destination-offset: inserting with this offset
    /// renders the piece on its origin square, and the animation settles it
    /// onto its natural destination offset.
    private func travelDelta(from origin: Square, to destination: Square, squareSide: CGFloat) -> CGSize {
        let start = offset(for: origin, squareSide: squareSide)
        let end = offset(for: destination, squareSide: squareSide)
        return CGSize(width: start.width - end.width, height: start.height - end.height)
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
