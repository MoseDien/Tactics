import SwiftUI
import ChessCore
import TacticsData

/// Everything the board animates on, in one value.
struct BoardAnimation: Equatable {
    /// For each square that gained a piece in this render, the square that
    /// piece visually arrived from (the view model derives it — committed
    /// moves, wrong-move preview, snap-back, castling rook). Empty when no
    /// move is attached, i.e. a puzzle load.
    var arrival: [Square: Square] = [:]
    /// Whether pieces slide between squares (debug toggle).
    var movesEnabled = true
    /// Whether a freshly presented board fades its pieces in (debug toggle).
    var setupEnabled = true
    /// Changes on every puzzle load. Baked into every piece id so a load
    /// presents entirely new views — insertion transitions apply, and no
    /// carried-over piece can interpolate its offset across the load (the
    /// "pieces fly across the board" defect).
    var boardGeneration = 0
    /// Monotonic token for each committed or preview move. Unlike pieceCount,
    /// this changes for ordinary non-capturing moves as well.
    var moveRevision = 0

    /// A board with no animation input — the review player's default.
    static let passthrough = BoardAnimation(arrival: [:], movesEnabled: true, setupEnabled: false, boardGeneration: 0, moveRevision: 0)

    /// Distance-adaptive slide timing: constant start-up cost plus a per-square
    /// cost, i.e. a roughly constant travel speed (the convention chess UIs
    /// use). A one-square step finishes in 135ms; a rook sweeping the board
    /// takes 405ms.
    static let slideBaseDuration: TimeInterval = 0.09
    static let slideDurationPerSquare: TimeInterval = 0.045
}

struct ChessBoardView: View {
    let position: [Square: Piece]
    let selectedSquare: Square?
    let hintMove: ChessMove?
    let lastMove: ChessMove?
    let isFlipped: Bool
    var animation: BoardAnimation = .passthrough
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
    /// (piece + square + generation), so SwiftUI treats it as remove-at-origin
    /// + insert-at-destination; the insertion transition slides the arriving
    /// piece in from the square `animation.arrival` names. Removals are
    /// identity (captured pieces vanish; a stale slide-away would look wrong).
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
        // The single animation declaration. A move (non-empty arrival map)
        // plays each arrival's slide. A puzzle load (empty arrival map, new
        // generation) fades the fresh pieces in — the generation is baked
        // into every id, so a load presents brand-new views whose insertion
        // transition is the fade, and no carried-over piece exists to
        // interpolate its offset across the load. Board flips don't change
        // `position`; Reduce Motion renders everything instantly.
        .animation(transactionAnimation, value: boardStamp)
    }

    /// What the animation modifier observes — a move and a board load each
    /// change it exactly once.
    private var boardStamp: BoardStamp {
        BoardStamp(
            pieceCount: position.count,
            generation: animation.boardGeneration,
            hasArrivals: !animation.arrival.isEmpty,
            moveRevision: animation.moveRevision
        )
    }

    private struct BoardStamp: Equatable {
        var pieceCount: Int
        var generation: Int
        var hasArrivals: Bool
        var moveRevision: Int
    }

    /// The container animation. A move's duration comes from that move's
    /// longest travel (castling moves two pieces; the king and rook lengths
    /// differ by one square at most), so a one-square step finishes fast and
    /// a board-sweep takes its time. The setup fade keeps one fixed duration.
    private var transactionAnimation: Animation? {
        guard !reduceMotion, animation.movesEnabled else { return nil }
        if !animation.arrival.isEmpty {
            return .easeOut(duration: moveSlideDuration)
        }
        if animation.setupEnabled { return moveAnimation }
        return nil
    }

    /// Longest Chebyshev distance among this render's arrivals, mapped
    /// through the constant-speed model.
    private var moveSlideDuration: TimeInterval {
        let squares = animation.arrival
            .map { destination, origin in
                max(abs(destination.file - origin.file), abs(destination.rank - origin.rank))
            }
            .max() ?? 1
        return BoardAnimation.slideBaseDuration
            + BoardAnimation.slideDurationPerSquare * TimeInterval(squares)
    }

    /// Pieces sorted by square notation for a stable z-order (dictionary
    /// iteration order would reshuffle the layering every move).
    private var piecePlacements: [(id: String, piece: Piece, square: Square)] {
        position
            .sorted { $0.key.notation < $1.key.notation }
            .map { ("\($0.value.assetName + $0.key.notation)#\(animation.boardGeneration)", $0.value, $0.key) }
    }

    /// Decision table for a piece's insertion: a move slides the arriving
    /// piece in, a load fades every piece in, everything else appears in place.
    private func transition(
        for placement: (id: String, piece: Piece, square: Square),
        squareSide: CGFloat
    ) -> AnyTransition {
        if let origin = animation.arrival[placement.square], animation.movesEnabled, !reduceMotion {
            return slideTransition(from: origin, to: placement.square, squareSide: squareSide)
        }
        if animation.setupEnabled, animation.arrival.isEmpty, animation.movesEnabled, !reduceMotion {
            return .opacity
        }
        return .identity
    }

    /// The arriving piece first renders on its origin square (origin-offset
    /// minus destination-offset); the container's transaction animation —
    /// whose duration this move's longest travel sets — settles it into place.
    private func slideTransition(from origin: Square, to destination: Square, squareSide: CGFloat) -> AnyTransition {
        let start = offset(for: origin, squareSide: squareSide)
        let end = offset(for: destination, squareSide: squareSide)
        return .asymmetric(
            insertion: .offset(CGSize(width: start.width - end.width, height: start.height - end.height)),
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
