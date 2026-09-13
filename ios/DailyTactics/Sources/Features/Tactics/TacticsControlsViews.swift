import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

/// The user's rating with the latest delta, shown above the move controls.
struct RatingPanelView: View {
    let viewModel: TacticsViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: "tactics.rating"))
                .font(.title3)
                .lineLimit(1)
            Text("\(viewModel.userRating)")
                .lineLimit(1)
            if let delta = viewModel.lastRatingDelta {
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

/// One row of dots: the per-puzzle outcomes of the current round.
struct RoundProgressView: View {
    let viewModel: TacticsViewModel

    var body: some View {
        PuzzleResultRow(outcomes: viewModel.results, currentIndex: viewModel.currentIndex)
            .padding(.top, 8)
    }
}

/// Flip / move counter / hint, between the board and the feedback area.
/// The counter sits at the row's true geometric center (overlay) — the sides
/// hold different content widths (flip + favorite vs. hint), so flow layout
/// with two spacers would push it off-center.
struct MoveControlsView: View {
    let viewModel: TacticsViewModel
    let onReviewCurrentPuzzle: () -> Void

    var body: some View {
        HStack {
            Button {
                viewModel.toggleBoardFlip()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel(String(localized: "tactics.flip_board"))

            favoriteButton

            Spacer()

            Button {
                if viewModel.canReviewCurrentPuzzle {
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
            .disabled(!viewModel.hintEnabled && !viewModel.canReviewCurrentPuzzle)
            .accessibilityLabel(String(localized: "tactics.hint"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay {
            moveCounter
        }
    }

    /// "2 / 3 · P" pinned to the row's center, whatever the sides hold.
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

    /// The favorite heart, right of the flip button. Outlines only: pink when
    /// favorited, gray otherwise. Appears once the puzzle is finished (play
    /// or review); hidden keeps its space so the center counter doesn't shift.
    @ViewBuilder
    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            Image(systemName: "heart")
                .foregroundStyle(viewModel.isCurrentFavorite ? Color.pink : Color.secondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .opacity(viewModel.currentPuzzleFinished ? 1 : 0)
        .allowsHitTesting(viewModel.currentPuzzleFinished)
        .accessibilityLabel(String(localized: viewModel.isCurrentFavorite ? "tactics.unfavorite" : "tactics.favorite"))
        .accessibilityHidden(!viewModel.currentPuzzleFinished)
    }
}

/// Result actions shown once a puzzle is complete, plus the available-next-
/// round action surfaced after a foreground refresh.
struct RoundActionsView: View {
    let viewModel: TacticsViewModel

    var body: some View {
        VStack(spacing: 12) {
            switch viewModel.feedbackState {
            case .puzzleComplete, .trainingComplete:
                completedPuzzleActions
            default:
                EmptyView()
            }

            // This uses the same leading action position as the completed
            // puzzle controls above, but is available in every active board
            // state after a foreground refresh opens a new round.
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
                if viewModel.mode == .reviewRound || viewModel.isRoundComplete {
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

/// The bottom-of-screen, transient message area. It keeps move-state
/// feedback separate from result/navigation controls above it.
struct TacticsMessageArea: View {
    let viewModel: TacticsViewModel

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
        let showsNextRoundButton = viewModel.currentPuzzleFinished
            && (viewModel.mode == .reviewRound || viewModel.isRoundComplete)
        guard showsNextRoundButton, !viewModel.isNewRoundAvailable else { return nil }
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

/// One control shared by the completed-round action row and the foreground
/// availability prompt.
struct NextRoundButton: View {
    let viewModel: TacticsViewModel

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

/// The four promotion choices shown over the board when a pawn reaches the
/// last rank. The move itself is only submitted once a piece is picked.
struct PromotionPickerView: View {
    let viewModel: TacticsViewModel
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
                            viewModel.choosePromotion(kind)
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
