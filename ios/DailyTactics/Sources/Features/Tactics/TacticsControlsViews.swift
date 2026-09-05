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
            Text("\(viewModel.userRating)")
            if let delta = viewModel.lastRatingDelta {
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(delta >= 0 ? Color.primary : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((delta >= 0 ? Color.green : Color.red).opacity(0.13))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }
}

/// One row of dots: the per-puzzle outcomes of the current batch.
struct RoundProgressView: View {
    let viewModel: TacticsViewModel

    var body: some View {
        PuzzleResultRow(outcomes: viewModel.results)
            .padding(.top, 8)
    }
}

/// Flip / move counter / hint, between the board and the feedback area.
struct MoveControlsView: View {
    let viewModel: TacticsViewModel

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

            HStack(spacing: 5) {
                Text("\(viewModel.currentMoveNumber) / \(viewModel.totalUserMoves)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(viewModel.mode == .reviewBatch ? "R" : "P")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(viewModel.mode == .reviewBatch ? Color.secondary : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel(String(localized: viewModel.mode == .reviewBatch ? "tactics.mode_review" : "tactics.mode_play"))
            }

            Spacer()

            Button {
                viewModel.requestHint()
            } label: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(!viewModel.hintEnabled)
            .accessibilityLabel(String(localized: "tactics.hint"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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

/// The status line under the board: what is happening right now, and the
/// next-puzzle / next-batch actions once a puzzle completes.
struct FeedbackView: View {
    let viewModel: TacticsViewModel

    var body: some View {
        switch viewModel.feedbackState {
        case .idle:
            EmptyView()
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case let .instruction(message, systemImage):
            Label(message, systemImage: systemImage)
                .foregroundStyle(.secondary)
        case .reviewing:
            Label(String(format: NSLocalizedString("tactics.reviewing_move", comment: "Review move progress"), viewModel.currentMoveNumber, viewModel.totalUserMoves), systemImage: "eye")
                .foregroundStyle(.secondary)
        case .opponentMoving:
            HStack(spacing: 10) {
                ProgressView()
                Text(String(localized: "tactics.opponent_moving"))
            }
            .foregroundStyle(.secondary)
        case .opponentReply:
            Label(String(localized: "tactics.opponent_reply"), systemImage: "arrow.left.and.right")
                .foregroundStyle(.secondary)
        case .incorrectMove:
            Label(String(localized: "tactics.incorrect_move"), systemImage: "arrow.counterclockwise")
                .foregroundStyle(.orange)
        case .puzzleComplete, .trainingComplete:
            VStack(spacing: 12) {
                HStack {
                    if viewModel.mode == .reviewBatch || viewModel.isBatchComplete {
                        Button(String(localized: "tactics.next_batch"), action: viewModel.startNextBatch)
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.isNewBatchAvailable ? .accentColor : Color.gray)
                    }
                    Spacer()
                    Button(String(localized: "tactics.next_puzzle"), action: viewModel.nextPuzzle)
                        .buttonStyle(.borderedProminent)
                }
                if let cooldown = viewModel.batchCooldownMessage {
                    Label(cooldown, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 28)
        }
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
