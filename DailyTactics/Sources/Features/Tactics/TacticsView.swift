import SwiftUI

struct TacticsView: View {
    @State private var viewModel = TacticsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.vertical, 28)

                    ChessBoardView(
                        position: viewModel.position,
                        selectedSquare: viewModel.selectedSquare,
                        lastMove: viewModel.session.lastMove,
                        onSelect: viewModel.select
                    )

                    feedback
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("DailyTactics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.start()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("TODAY'S PUZZLE")
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
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var feedback: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else {
            switch viewModel.state {
        case .loading:
            ProgressView()
        case .waitingForMove:
            Label("Find the winning move", systemImage: "scope")
                .foregroundStyle(.secondary)
        case .opponentMoving:
            HStack(spacing: 10) {
                ProgressView()
                Text("Opponent is moving…")
            }
            .foregroundStyle(.secondary)
        case .incorrectMove:
            Label("Not quite — look for a forcing move.", systemImage: "arrow.counterclockwise")
                .foregroundStyle(.orange)
        case .solved:
            VStack(spacing: 12) {
                Label("Checkmate! Puzzle solved.", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button("Play again", action: viewModel.restart)
                    .buttonStyle(.borderedProminent)
            }
        case .showingSolution:
            EmptyView()
            }
        }
    }
}

#Preview {
    TacticsView()
}
