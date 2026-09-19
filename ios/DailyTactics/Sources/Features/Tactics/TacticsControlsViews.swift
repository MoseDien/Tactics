import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

struct RatingPanelView: View {
    let viewModel: TacticsRatingViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: "tactics.rating"))
                .font(.title3)
                .lineLimit(1)
            Text("\(viewModel.rating)")
                .lineLimit(1)
            if let delta = viewModel.latestDelta {
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(delta >= 0 ? Color.accentColor : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((delta >= 0 ? Color.green : Color.red).opacity(0.13))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }
}

struct RoundProgressView: View {
    let viewModel: TacticsProgressViewModel

    var body: some View {
        PuzzleResultRow(outcomes: viewModel.outcomes, currentIndex: viewModel.currentIndex)
            .padding(.top, 8)
    }
}

/// Board tools / counter / hint. The counter is an overlay: the sides hold
/// different widths (analysis+favorite vs hint), so flow layout would off-center it.
struct MoveControlsView: View {
    let viewModel: TacticsControlsViewModel
    let onReviewCurrentPuzzle: () -> Void
    let onOpenAnalysis: () -> Void

    var body: some View {
        HStack {
            Button {
                onOpenAnalysis()
            } label: {
                Image(systemName: "checkerboard.rectangle")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel(String(localized: "tactics.open_analysis"))

            favoriteButton

            Spacer()

            Button {
                if viewModel.canReviewPuzzle {
                    onReviewCurrentPuzzle()
                } else {
                    viewModel.requestHint()
                }
            } label: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(!viewModel.canUseHint && !viewModel.canReviewPuzzle)
            .accessibilityLabel(String(localized: "tactics.hint"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay {
            moveCounter
        }
    }

    private var moveCounter: some View {
        HStack(spacing: 5) {
            Text("\(viewModel.currentMoveNumber) / \(viewModel.totalUserMoves)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Text(viewModel.mode == .reviewRound ? "R" : "P")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(viewModel.mode == .reviewRound ? Color.secondary : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel(String(localized: viewModel.mode == .reviewRound ? "tactics.mode_review" : "tactics.mode_play"))
        }
        .accessibilityElement(children: .combine)
    }

    /// Pink when favorited; hidden (space kept) until the puzzle finishes.
    @ViewBuilder
    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            Image(systemName: "heart")
                .foregroundStyle(viewModel.isFavorite ? Color.pink : Color.secondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .opacity(viewModel.isFinished ? 1 : 0)
        .allowsHitTesting(viewModel.isFinished)
        .accessibilityLabel(String(localized: viewModel.isFavorite ? "tactics.unfavorite" : "tactics.favorite"))
        .accessibilityHidden(!viewModel.isFinished)
    }
}

/// Result actions shown once a puzzle is complete, plus the available-next-
/// round action surfaced after a foreground refresh.
struct RoundActionsView: View {
    let viewModel: TacticsRoundActionsViewModel

    var body: some View {
        VStack(spacing: 12) {
            switch viewModel.feedbackState {
            case .puzzleComplete, .trainingComplete:
                completedPuzzleActions
            default:
                EmptyView()
            }

            if viewModel.shouldShowNewRoundAction {
                HStack {
                    NextRoundButton(viewModel: viewModel)
                    Spacer()
                }
                .padding(.bottom, 28)
            }
        }
    }

    private var completedPuzzleActions: some View {
        VStack(spacing: 12) {
            HStack {
                if viewModel.showsCompletedRoundAction {
                    NextRoundButton(viewModel: viewModel)
                }
                Spacer()
                Button(String(localized: "tactics.next_puzzle"), action: viewModel.nextPuzzle)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.bottom, 28)
    }

}

/// Transient move-state messages, kept below the result/navigation actions.
struct TacticsMessageArea: View {
    let viewModel: TacticsMessageAreaViewModel

    var hasMessage: Bool {
        let hasStateMessage = switch viewModel.feedbackState {
        case .idle, .puzzleComplete, .trainingComplete:
            false
        default:
            true
        }
        return hasStateMessage || nextRoundUnlockMessage != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch viewModel.feedbackState {
                case let .error(message):
                    messageRow(message, systemImage: "exclamationmark.triangle.fill", color: .red)
                case let .instruction(message, systemImage):
                    messageRow(message, systemImage: systemImage, color: .secondary)
                case .reviewing:
                    messageRow(
                        String(format: NSLocalizedString("tactics.reviewing_move", comment: "Review move progress"), viewModel.currentMoveNumber, viewModel.totalUserMoves),
                        systemImage: "eye",
                        color: .secondary
                    )
                case .opponentMoving:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(String(localized: "tactics.opponent_moving"))
                    }
                    .foregroundStyle(.secondary)
                    .messageContainer()
                case .opponentReply:
                    messageRow(String(localized: "tactics.opponent_reply"), systemImage: "arrow.left.and.right", color: .secondary)
                case .incorrectMove:
                    messageRow(String(localized: "tactics.incorrect_move"), systemImage: "arrow.counterclockwise", color: .orange)
                case .idle, .puzzleComplete, .trainingComplete:
                    EmptyView()
                }
            }

            if let nextRoundUnlockMessage {
                messageRow(nextRoundUnlockMessage, systemImage: "clock", color: .secondary)
            }
        }
    }

    private var nextRoundUnlockMessage: String? {
        guard viewModel.showsNextRoundUnlock else { return nil }
        return viewModel.nextRoundUnlockDescription
    }

    private func messageRow(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(color)
            .messageContainer()
    }
}

private extension View {
    func messageContainer() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .font(.subheadline)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NextRoundButton: View {
    let viewModel: TacticsRoundActionsViewModel

    var body: some View {
        Button(String(localized: "tactics.next_round"), action: viewModel.startNextRound)
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isNewRoundAvailable ? .accentColor : Color.gray)
            .disabled(!viewModel.isNewRoundAvailable)
            .accessibilityHint(viewModel.isNewRoundAvailable
                ? String(localized: "tactics.next_round_ready_hint")
                : String(localized: "tactics.next_round_wait_hint"))
    }
}

/// Four promotion choices; the move submits only after a pick.
struct PromotionPickerView: View {
    let viewModel: TacticsPromotionViewModel
    let promotion: (from: Square, to: Square)

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text(String(localized: "tactics.promotion_title"))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 18) {
                    ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                        Button {
                            viewModel.choose(kind)
                        } label: {
                            Image(Piece(color: viewModel.playerColor, kind: kind).assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .padding(6)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel(String(localized: "tactics.promotion_\(kind.rawValue)"))
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(24)
            Spacer()
        }
    }
}
