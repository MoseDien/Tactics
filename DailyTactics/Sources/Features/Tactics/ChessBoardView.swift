import SwiftUI

struct ChessBoardView: View {
    let position: [Square: Piece]
    let selectedSquare: Square?
    let lastMove: ChessMove?
    let onSelect: (Square) -> Void

    private let lightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)
    private let darkSquare = Color(red: 0.71, green: 0.52, blue: 0.36)
    private let moveHighlight = Color(red: 0.76, green: 0.80, blue: 0.25)
    private let selectedHighlight = Color(red: 0.65, green: 0.69, blue: 0.10)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSide = side / 8

            VStack(spacing: 0) {
                ForEach((0..<8).reversed(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            let square = Square(file: file, rank: rank)
                            Button {
                                onSelect(square)
                            } label: {
                                ZStack {
                                    ((file + rank).isMultiple(of: 2) ? darkSquare : lightSquare)

                                    if lastMove?.from == square || lastMove?.to == square {
                                        moveHighlight.opacity(0.82)
                                    }

                                    if selectedSquare == square {
                                        selectedHighlight.opacity(0.88)
                                    }

                                    if let piece = position[square] {
                                        Image(piece.assetName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: squareSide * 0.88, height: squareSide * 0.88)
                                            .accessibilityHidden(true)
                                    }

                                    coordinateLabels(for: square)
                                }
                                .frame(width: squareSide, height: squareSide)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: square))
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func coordinateLabels(for square: Square) -> some View {
        VStack {
            HStack {
                if square.file == 7 {
                    Text("\(square.rank + 1)")
                }
                Spacer()
            }
            Spacer()
            HStack {
                if square.rank == 0 {
                    Text(String(square.notation.prefix(1)))
                }
                Spacer()
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle((square.file + square.rank).isMultiple(of: 2) ? lightSquare : darkSquare)
        .padding(4)
    }

    private func accessibilityLabel(for square: Square) -> String {
        if let piece = position[square] {
            return "\(piece.color.rawValue) \(piece.kind.rawValue) on \(square.notation)"
        }
        return "Empty square \(square.notation)"
    }
}
