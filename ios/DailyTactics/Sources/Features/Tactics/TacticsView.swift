import SwiftUI
import SwiftData

struct TacticsView: View {
    let mode: TacticsMode
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TacticsViewModel?
    @State private var showingSettings = false
    @State private var reviewPuzzle: Puzzle?
    @State private var showingPuzzleDetails = false
    @State private var currentDate = Date()

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
            // Round 1 is fetched from the store exactly once, here. Subsequent
            // rounds come from `viewModel.restartBatch()`, which queries the
            // store again only at that round boundary. An empty result (e.g. an
            // empty preview container) falls back to the bundled samples so the
            // board is never blank.
            let store = PuzzleProgressStore(context: modelContext)
            var round: [Puzzle]
            if mode == .reviewBatch {
                round = BatchStore.currentPuzzles(from: store.allPuzzles())
            } else {
                round = store.fetchUnattemptedRound(count: BatchConfiguration.puzzleCount)
            }
            if round.isEmpty { round = Puzzle.samples }
            if mode == .play { BatchStore.begin(with: round) }
            let vm = TacticsViewModel(dataset: round, progress: store, dailyPuzzleCount: BatchConfiguration.puzzleCount, mode: mode)
            vm.start()
            viewModel = vm
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
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
            .sheet(item: $reviewPuzzle) { puzzle in
                ReviewPuzzleView(puzzle: puzzle)
            }
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
                .accessibilityHint("Tap to reveal the puzzle rating and play count")
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
                Text(viewModel.mode == .play ? "P" : "R")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(viewModel.mode == .play ? Color.accentColor : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel(viewModel.mode == .play ? "Play mode" : "Review mode")
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
            .disabled(viewModel.mode == .play && !viewModel.hintEnabled)
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
            HStack(spacing: 24) {
                Button(String(localized: "common.review")) {
                    reviewPuzzle = viewModel.puzzles[viewModel.currentIndex]
                }.buttonStyle(.bordered)
                
                if viewModel.mode == .reviewBatch {
                    Button(String(localized: "tactics.next_puzzle"), action: viewModel.nextPuzzle)
                        .buttonStyle(.bordered)
                    if viewModel.canStartNewBatch {
                        Button(String(localized: "tactics.next_batch"), action: viewModel.startNextBatch)
                            .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.isBatchComplete {
                    Button(String(localized: "tactics.next_batch"), action: viewModel.startNextBatch)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "tactics.next_puzzle"), action: viewModel.nextPuzzle)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 28)
        }
    }
}

#Preview {
    TacticsView()
        .modelContainer(for: [PuzzleProgress.self, PuzzleRecord.self], inMemory: true)
}
