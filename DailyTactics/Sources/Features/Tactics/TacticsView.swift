import SwiftUI
import SwiftData

struct TacticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TacticsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.vertical, 28)

                    ChessBoardView(
                        position: viewModel.displayedPosition,
                        selectedSquare: viewModel.selectedSquare,
                        lastMove: viewModel.session.lastMove,
                        isFlipped: viewModel.isBoardFlipped,
                        onSelect: viewModel.select
                    )

                    moveControls

                    feedback
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("DailyTactics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.attachProgress(PuzzleProgressStore(context: modelContext))
                viewModel.start()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("PUZZLE \(viewModel.puzzleNumber) OF \(viewModel.puzzleCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            Text("Find the winning line")
                .font(.largeTitle.bold())

            Label(
                "\(viewModel.playerColor == .white ? "White" : "Black") to move",
                systemImage: "circle.lefthalf.filled"
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.completedCount > 0 {
                Label("Solved: \(viewModel.completedCount)", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var moveControls: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.stepBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.canStepBack ? Color.primary : Color.secondary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(!viewModel.canStepBack)
            .accessibilityLabel("Previous move")

            Text("\(viewModel.currentMoveNumber) / \(viewModel.totalUserMoves)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)

            Button {
                viewModel.stepForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.canStepForward ? Color.primary : Color.secondary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .disabled(!viewModel.canStepForward)
            .accessibilityLabel("Next move")

            Divider()
                .frame(height: 30)
                .opacity(0.5)

            Button {
                viewModel.toggleBoardFlip()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel("Flip board")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var feedback: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else {
            switch viewModel.state {
        case .waitingForMove:
            Label("Find the winning move", systemImage: "scope")
                .foregroundStyle(.secondary)
        case .opponentMoving:
            if viewModel.isReviewing {
                Label("Opponent's reply", systemImage: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Opponent is moving…")
                }
                .foregroundStyle(.secondary)
            }
        case .incorrectMove:
            Label("Not quite — look for a forcing move.", systemImage: "arrow.counterclockwise")
                .foregroundStyle(.orange)
        case .solved:
            VStack(spacing: 12) {
                if viewModel.isBatchComplete {
                    Label("All \(viewModel.puzzleCount) puzzles complete!", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Label("Puzzle solved.", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
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
}

#Preview {
    TacticsView()
        .modelContainer(for: PuzzleProgress.self, inMemory: true)
}
