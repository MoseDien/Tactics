import SwiftUI

/// The free analysis board sheet: seeded from the puzzle's machine-first
/// opening position, both sides playable, read-only with respect to training.
struct AnalysisScreenView: View {
    let seedFEN: String
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
            Button(String(localized: "common.done")) { dismiss() }
        }
        .task {
            if store == nil {
                store = AnalysisGameStore(seedFEN: seedFEN)
            }
        }
    }

    private func content(for store: AnalysisGameStore) -> some View {
        VStack(spacing: 14) {
            statusLine(for: store)

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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .overlay {
            if let pending = store.pendingPromotion {
                AnalysisPromotionPicker(store: store, pending: pending)
            }
        }
    }

    private func statusLine(for store: AnalysisGameStore) -> some View {
        let (text, imageName) = statusCopy(for: store.status, activeColor: store.position.activeColor)
        return HStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer()
        }
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
        HStack(spacing: 14) {
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

            Spacer()
            controlButton(symbol: "arrow.up.arrow.down", label: "tactics.flip_board", isDisabled: false) {
                store.flip()
            }
        }
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
