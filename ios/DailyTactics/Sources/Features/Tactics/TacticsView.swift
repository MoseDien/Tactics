import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

struct TacticsView: View {
    let mode: TacticsMode
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: TacticsViewModel?
    @State private var showingSettings = false
    @State private var showingPuzzleDetails = false

    init(mode: TacticsMode = .play) { self.mode = mode }

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading…")
            }
        }
        .task {
            // Top up the library first: if the unattempted pool can't fill a
            // batch, fetch the next remote chunk (silently skipped offline).
            _ = await dependencies.provisioner.ensureBatchAvailable(minimum: BatchPolicy.puzzleCount)
            let vm = TacticsViewModel(
                dependencies: dependencies,
                dailyPuzzleCount: BatchPolicy.puzzleCount,
                mode: mode
            )
            vm.start()
            viewModel = vm
        }
    }

    @ViewBuilder
    private func content(for viewModel: TacticsViewModel) -> some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                    header(for: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                    ChessBoardView(
                        position: viewModel.displayedPosition,
                        selectedSquare: viewModel.selectedSquare,
                        hintMove: viewModel.hintMove,
                        lastMove: viewModel.lastMove,
                        isFlipped: viewModel.isBoardFlipped,
                        previewMove: viewModel.attemptedMove,
                        snapbackMove: viewModel.snapbackMove,
                        onSelect: viewModel.select
                    )
                    .frame(width: min(viewport.size.width, max(280, viewport.size.height - 238)))

                    HStack(alignment: .center, spacing: 12) {
                        ratingPanel(for: viewModel)
                        Spacer(minLength: 8)
                        roundProgress(for: viewModel)
                    }
                    .padding(.horizontal, 4)

                    moveControls(for: viewModel)

                    feedback(for: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                }
            }
            .overlay {
                if let promotion = viewModel.pendingPromotion {
                    promotionPicker(for: viewModel, promotion: promotion)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(String(localized: "app.name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "tactics.settings"))
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    /// The four promotion choices shown over the board when a pawn reaches the
    /// last rank. The move itself is only submitted once a piece is picked.
    private func promotionPicker(for viewModel: TacticsViewModel, promotion: (from: Square, to: Square)) -> some View {
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

    private func header(for viewModel: TacticsViewModel) -> some View {
        VStack(spacing: 5) {
            Text(String(format: NSLocalizedString("tactics.puzzle_progress", comment: "Puzzle progress"), viewModel.puzzleNumber, viewModel.puzzleCount))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            HStack(spacing: 14) {
                HStack {
                    Image(viewModel.playerColor == .white ? "wK" : "bK")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .frame(width: 54, height: 54)
                        .background(Color(red: 0.94, green: 0.85, blue: 0.70))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.headerTitle)
                            // .font(.headline.bold())
                        Text(viewModel.headerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
                
                Button {
                    showingPuzzleDetails.toggle()
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { level in
                                Image(systemName: level <= difficultyLevel(for: viewModel.currentPuzzleRating) ? "star.fill" : "star")
                                    .foregroundStyle(level <= difficultyLevel(for: viewModel.currentPuzzleRating) ? Color.primary : Color.secondary.opacity(0.45))
                            }
                        }
                        if showingPuzzleDetails {
                            HStack(spacing: 8) {
                                if let rating = viewModel.currentPuzzleRating {
                                    Label("\(rating)", systemImage: "gauge.medium")
                                }
                                if let plays = viewModel.currentPuzzlePlayCount {
                                    Label(plays.formatted(), systemImage: "play.circle")
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "tactics.puzzle_difficulty"))
                .accessibilityHint(String(localized: "tactics.puzzle_difficulty_hint"))
            }
            .padding(8)
            .background(Color(.secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        }
        .frame(maxWidth: .infinity)
    }

    private func difficultyLevel(for rating: Int?) -> Int {
        guard let rating else { return 3 }
        return min(5, max(1, (rating - 800) / 240 + 1))
    }

    private func moveControls(for viewModel: TacticsViewModel) -> some View {
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

    private func roundProgress(for viewModel: TacticsViewModel) -> some View {
        PuzzleResultRow(outcomes: viewModel.results)
            .padding(.top, 8)
    }

    private func ratingPanel(for viewModel: TacticsViewModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: "tactics.rating"))
                .font(.title3)
            Text("\(viewModel.userRating)")
                //.font(.title2.bold().monospacedDigit())
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

    @ViewBuilder
    private func feedback(for viewModel: TacticsViewModel) -> some View {
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

#Preview {
    TacticsView()
        .environment(AppDependencies.preview())
}
