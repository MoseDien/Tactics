import SwiftUI
import SwiftData

struct TacticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TacticsViewModel
    @State private var showingSettings = false
    @State private var showLevelTransition = false

    init(dataset: [Puzzle] = Puzzle.loadBundled(), dailyPuzzleCount: Int = 5) {
        _viewModel = State(initialValue: TacticsViewModel(dataset: dataset.isEmpty ? Puzzle.loadBundled() : dataset, dailyPuzzleCount: dailyPuzzleCount))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                    header
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

                    ratingPanel

                    moveControls

                    feedback
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("DailyTactics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                viewModel.attachProgress(PuzzleProgressStore(context: modelContext))
                viewModel.start()
            }
            .onChange(of: viewModel.levelTransition) { _, newLevel in
                showLevelTransition = newLevel != nil
            }
            .alert("New rating level", isPresented: $showLevelTransition) {
                Button("Load \(viewModel.levelTransition?.rawValue ?? "next") puzzles") {
                    importLevelData()
                }
            } message: {
                Text("Your rating is now \(viewModel.userRating), so your level is \(viewModel.levelTransition?.rawValue ?? "updated").")
            }
        }
    }

    private func importLevelData() {
        Task { @MainActor in
            let importer = PuzzleLibraryImporter(context: modelContext)
            await importer.importBundled(for: viewModel.userRating) { _ in }
            // Refresh the in-memory dataset from SwiftData so the new tier's
            // puzzles actually reach the board (the init-time snapshot is stale).
            let level = RatingLevel(rating: viewModel.userRating)
            let scoped = ((try? modelContext.fetch(FetchDescriptor<PuzzleRecord>())) ?? [])
                .filter { level.ratingRange.contains($0.rating) }
                .map(\.puzzle)
            viewModel.reload(dataset: scoped)
            viewModel.acknowledgeLevelTransition()
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text("PUZZLE \(viewModel.puzzleNumber) OF \(viewModel.puzzleCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            HStack(spacing: 14) {
                Image(viewModel.playerColor == .white ? "wK" : "bK")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: 54, height: 54)
                    .background(Color(red: 0.94, green: 0.85, blue: 0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.headerTitle)
                        .font(.headline.bold())
                    Text(viewModel.headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(.secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        }
        .frame(maxWidth: .infinity)
    }

    private var moveControls: some View {
        HStack {
            Button {
                viewModel.toggleBoardFlip()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel("Flip board")

            Spacer(minLength: 24)

            Button {
                viewModel.requestHint()
            } label: {
                Image(systemName: "lightbulb")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.hintEnabled ? Color.primary : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(!viewModel.hintEnabled)
            .accessibilityLabel("Hint")

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Button {
                    viewModel.stepBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(viewModel.canStepBack ? Color.primary : Color.secondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .disabled(!viewModel.canStepBack)
                .accessibilityLabel("Previous move")

                Text("\(viewModel.currentMoveNumber) / \(viewModel.totalUserMoves)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36)

                Button {
                    viewModel.stepForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(viewModel.canStepForward ? Color.primary : Color.secondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .disabled(!viewModel.canStepForward)
                .accessibilityLabel("Next move")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var ratingPanel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Rating")
                .font(.title3)
            Text("\(viewModel.userRating)")
                .font(.title2.bold().monospacedDigit())
            if let delta = viewModel.lastRatingDelta {
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(delta >= 0 ? .green : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((delta >= 0 ? Color.green : Color.red).opacity(0.13))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var feedback: some View {
        switch viewModel.feedbackState {
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case let .instruction(message, systemImage):
            Label(message, systemImage: systemImage)
                .foregroundStyle(.secondary)
        case .reviewing:
            Label("Reviewing move \(viewModel.currentMoveNumber) / \(viewModel.totalUserMoves)", systemImage: "eye")
                .foregroundStyle(.secondary)
        case .opponentMoving:
            HStack(spacing: 10) {
                ProgressView()
                Text("Opponent is moving…")
            }
            .foregroundStyle(.secondary)
        case .opponentReply:
                Label("Opponent's reply", systemImage: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
        case .incorrectMove:
            Label("Not quite — look for a forcing move.", systemImage: "arrow.counterclockwise")
                .foregroundStyle(.orange)
        case .puzzleComplete, .trainingComplete:
            VStack(spacing: 12) {
                if case .trainingComplete = viewModel.feedbackState {
                    Label("Training complete!", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Label("Puzzle complete!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }

                if let delta = viewModel.lastRatingDelta {
                    Text(delta >= 0 ? "Rating changed by +\(delta)" : "Rating changed by \(delta)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Play again", action: viewModel.restart)
                        .buttonStyle(.bordered)
                    if viewModel.isBatchComplete {
                        Button("Start over", action: viewModel.restartBatch)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Next puzzle", action: viewModel.nextPuzzle)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

#Preview {
    TacticsView()
        .modelContainer(for: PuzzleProgress.self, inMemory: true)
}
