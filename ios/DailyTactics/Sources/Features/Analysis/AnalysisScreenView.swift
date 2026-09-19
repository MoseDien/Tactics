import SwiftUI

/// The free analysis board sheet: seeded from the puzzle's raw position with
/// the machine's opening move as history frame one (highlighted; rewinding to
/// the bottom replays it), and oriented like the training board it launched
/// from. Both sides playable, read-only with respect to training.
struct AnalysisScreenView: View {
    let seedFEN: String
    var openingMove: Analysis.Move? = nil
    var startsFlipped: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var store: AnalysisGameStore?

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "analysis.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                dismiss()
            } label: {
                Text(String(localized: "common.done"))
                    .bold()
            }
        }
        .task {
            if store == nil {
                store = AnalysisGameStore(
                    seedFEN: seedFEN,
                    openingMove: openingMove,
                    startsFlipped: startsFlipped
                )
            }
        }
    }

    private func content(for store: AnalysisGameStore) -> some View {
        VStack(spacing: 12) {
            statusBand(for: store)

            AnalysisBoardGridView(
                position: store.position,
                selectedSquare: store.selectedSquare,
                legalTargets: store.legalTargets,
                lastMove: store.lastMove,
                isFlipped: store.isFlipped,
                animation: AnalysisBoardAnimation(
                    arrival: store.animatedArrival,
                    boardGeneration: store.boardGeneration,
                    moveRevision: store.moveRevision,
                    isUndo: store.isUndoAnimation
                ),
                onSelect: { store.select($0) }
            )

            controlsRow(for: store)

            Text(String(localized: "analysis.free_move_hint"))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // The strip lives in the safe-area inset, outside the content flow:
        // a single fixed-height row, it never disturbs the layout below.
        .safeAreaInset(edge: .top, spacing: 12) {
            if !store.moveList.isEmpty {
                moveStrip(for: store)
                    .padding(.top, 12)
            }
        }
        .safeAreaPadding(.bottom, 24)
        .overlay {
            if let pending = store.pendingPromotion {
                AnalysisPromotionPicker(store: store, pending: pending)
            }
        }
    }

    /// The framed status band: the current side-to-move's king at the left,
    /// then two lines — "you hold white/black" (hidden on an unseeded free
    /// board) over the live status — with the material badge at the right.
    /// Framed like the board: warm light-square fill, dark-square border.
    private func statusBand(for store: AnalysisGameStore) -> some View {
        let (statusText, imageName) = statusCopy(for: store.status, activeColor: store.position.activeColor)
        return HStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                if let heldColor = store.heldColor {
                    Text(String(localized: heldColor == .white ? "analysis.you_hold_white" : "analysis.you_hold_black"))
                }
                
                Text(statusText)
                    .backgroundStyle(.gray)
            }
            Spacer()
            materialBalance(for: store)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Self.boardLightSquare, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Self.boardDarkSquare, lineWidth: 1)
        }
        .padding(.horizontal, 12)
    }

    /// The board's own square palette, mirrored so the band reads as part of
    /// it (the same literals `ChessBoardView` and `AnalysisBoardGridView`
    /// each keep independently).
    private static let boardLightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)
    private static let boardDarkSquare = Color(red: 0.71, green: 0.52, blue: 0.36)

    /// Material comparison, lichess-style: only the leading side shows a
    /// badge (pawn 1, knight/bishop 3, rook 5, queen 9); equal material
    /// keeps the line clean.
    private func materialBalance(for store: AnalysisGameStore) -> some View {
        let balance = store.position.materialBalance
        return HStack(spacing: 8) {
            if balance > 0 {
                advantageBadge(color: .white, asset: "wP", advantage: balance)
            }
            if balance < 0 {
                advantageBadge(color: .black, asset: "bP", advantage: -balance)
            }
        }
    }

    private func advantageBadge(color: Analysis.Color, asset: String, advantage: Int) -> some View {
        HStack(spacing: 3) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
            Text("+\(advantage)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: NSLocalizedString("analysis.material_advantage", comment: ""),
            NSLocalizedString(color == .white ? "piece.white.name" : "piece.black.name", comment: ""),
            advantage
        ))
    }

    /// The played line as numbered SAN chips, each led by the moving piece's
    /// icon; one horizontally scrolling row that tracks the latest move.
    private func moveStrip(for store: AnalysisGameStore) -> some View {
        let list = store.moveList
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.offset) { index, display in
                        moveChip(display, numberPrefix: numberPrefix(at: index, in: list))
                            .id(index)
                    }
                }
                .padding(.horizontal, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "analysis.move_list"))
            .onAppear {
                proxy.scrollTo(list.count - 1, anchor: .trailing)
            }
            .onChange(of: store.moveRevision) { _, _ in
                proxy.scrollTo(list.count - 1, anchor: .trailing)
            }
        }
    }

    /// One number per fullmove pair ("1. e4 e5"): white's move carries it; a
    /// black move only does when the line opens on it ("1… e5").
    private func numberPrefix(at index: Int, in list: [Analysis.MoveDisplay]) -> String? {
        let display = list[index]
        if display.piece.color == .white { return "\(display.number)." }
        return index == 0 ? "\(display.number)…" : nil
    }

    private func moveChip(_ display: Analysis.MoveDisplay, numberPrefix: String?) -> some View {
        HStack(spacing: 3) {
            if let numberPrefix {
                Text(numberPrefix)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Image(display.piece.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
            Text(display.san)
                .font(.footnote.weight(.semibold))
                .monospaced()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chipAccessibilityLabel(for: display, numberPrefix: numberPrefix))
    }

    private func chipAccessibilityLabel(
        for display: Analysis.MoveDisplay,
        numberPrefix: String?
    ) -> String {
        let side = NSLocalizedString(
            display.piece.color == .white ? "piece.white.name" : "piece.black.name", comment: ""
        )
        let kind = NSLocalizedString("piece.\(display.piece.kind.rawValue).name", comment: "")
        let prefix = numberPrefix.map { "\($0) " } ?? ""
        return "\(prefix)\(side) \(kind) \(display.san)"
    }

    private func statusCopy(
        for status: Analysis.Status,
        activeColor: Analysis.Color
    ) -> (text: String, imageName: String) {
        let kingAsset = activeColor == .white ? "wK" : "bK"
        switch status {
        case .playing:
            return (String(localized: activeColor == .white ? "analysis.status_white_to_move" : "analysis.status_black_to_move"), kingAsset)
        case .check:
            return (String(localized: "analysis.status_check"), kingAsset)
        case .checkmate(let winner):
            let side = NSLocalizedString(winner == .white ? "piece.white.name" : "piece.black.name", comment: "")
            return (String(format: NSLocalizedString("analysis.status_checkmate", comment: ""), side),
                    winner == .white ? "wK" : "bK")
        case .stalemate:
            return (String(localized: "analysis.status_stalemate"), "wK")
        }
    }

    private func controlsRow(for store: AnalysisGameStore) -> some View {
        HStack(spacing: 12) {
            controlButton(symbol: "arrow.up.arrow.down", label: "tactics.flip_board", isDisabled: false) {
                store.flip()
            }
            Spacer()

            // One back control: tap undoes a step, hold opens reset-to-seed.
            Menu {
                Button(String(localized: "analysis.reset")) {
                    store.reset()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            } primaryAction: {
                store.undo()
            }
            .disabled(!store.canUndo)
            .opacity(store.canUndo ? 1 : 0.4)
            .accessibilityLabel(String(localized: "analysis.undo"))
        }
        .padding(.horizontal, 12)
    }

    private func controlButton(
        symbol: String,
        label key: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(String(localized: String.LocalizationValue(key)))
    }
}

/// The four-piece promotion card; submits the queued move on a pick.
private struct AnalysisPromotionPicker: View {
    let store: AnalysisGameStore
    let pending: (from: Analysis.Square, to: Analysis.Square)

    var body: some View {
        VStack(spacing: 14) {
            Text(String(localized: "tactics.promotion_title"))
                .font(.headline)
            HStack(spacing: 12) {
                ForEach([Analysis.PieceKind.queen, .rook, .bishop, .knight], id: \.rawValue) { kind in
                    Button {
                        store.choosePromotion(kind)
                    } label: {
                        Image(Analysis.Piece(color: store.position.activeColor, kind: kind).assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .padding(6)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: promotionKey(for: kind)))
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(40)
    }

    private func promotionKey(for kind: Analysis.PieceKind) -> String.LocalizationValue {
        switch kind {
        case .queen: "tactics.promotion_queen"
        case .rook: "tactics.promotion_rook"
        case .bishop: "tactics.promotion_bishop"
        case .knight: "tactics.promotion_knight"
        case .king, .pawn: "tactics.promotion_queen"
        }
    }
}
