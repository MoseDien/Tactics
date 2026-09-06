import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

struct TacticsView: View {
    let mode: TacticsMode
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: TacticsViewModel?
    @State private var showingSettings = false

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
            // round, fetch the next remote chunk (silently skipped offline).
            _ = await dependencies.provisioner.ensureRoundAvailable(minimum: RoundPolicy.puzzleCount)
            let vm = TacticsViewModel(
                dependencies: dependencies,
                dailyPuzzleCount: RoundPolicy.puzzleCount,
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
                    TacticsHeaderView(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                    ChessBoardView(
                        position: viewModel.displayedPosition,
                        selectedSquare: viewModel.selectedSquare,
                        hintMove: viewModel.hintMove,
                        lastMove: viewModel.lastMove,
                        isFlipped: viewModel.isBoardFlipped,
                        animation: boardAnimation(for: viewModel),
                        onSelect: viewModel.select
                    )
                    .frame(width: min(viewport.size.width, max(280, viewport.size.height - 238)))

                    HStack(alignment: .center, spacing: 12) {
                        RatingPanelView(viewModel: viewModel)
                        Spacer(minLength: 8)
                        RoundProgressView(viewModel: viewModel)
                    }
                    .padding(.horizontal, 4)

                    MoveControlsView(viewModel: viewModel)

                    FeedbackView(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                }
            }
            .overlay {
                if let promotion = viewModel.pendingPromotion {
                    PromotionPickerView(viewModel: viewModel, promotion: promotion)
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

    /// Collects the board's animation inputs from their sources.
    private func boardAnimation(for viewModel: TacticsViewModel) -> BoardAnimation {
        BoardAnimation(
            arrival: viewModel.animatedArrival,
            movesEnabled: dependencies.pieceAnimation.isEnabled,
            setupEnabled: dependencies.pieceAnimation.isSetupEnabled,
            boardGeneration: viewModel.boardGeneration,
            moveRevision: viewModel.boardMoveRevision
        )
    }
}

#Preview {
    TacticsView()
        .environment(AppDependencies.preview())
}
