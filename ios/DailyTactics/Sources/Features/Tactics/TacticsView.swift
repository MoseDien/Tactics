import SwiftUI
import PuzzleKit
import ChessCore
import TacticsData

struct TacticsView: View {
    let mode: TacticsMode
    let resumesActiveRound: Bool
    @Environment(AppDependencies.self) private var dependencies
    @State private var screen: TacticsScreenViewModel?
    @State private var showingSettings = false
    @State private var showingHowToPlay = false
    @State private var reviewingPuzzle: Puzzle?
    @State private var analysisSeed: AnalysisSeed?

    /// Sheet payload for the free analysis board; reads the training board
    /// once, at open time.
    private struct AnalysisSeed: Identifiable {
        let fen: String
        var id: String { fen }
    }

    init(mode: TacticsMode = .play, resumesActiveRound: Bool = false) {
        self.mode = mode
        self.resumesActiveRound = resumesActiveRound
    }

    var body: some View {
        Group {
            if let screen {
                content(for: screen)
            } else {
                ProgressView("Loading…")
            }
        }
        .task {
            _ = await dependencies.provisioner.ensureRoundAvailable(minimum: RoundPolicy.puzzleCount)
            let training = TacticsTrainingStore(
                dependencies: dependencies,
                dailyPuzzleCount: RoundPolicy.puzzleCount,
                mode: mode,
                resumesActiveRound: resumesActiveRound
            )
            let screen = TacticsScreenViewModel(training: training)
            screen.start()
            self.screen = screen
            #if DEBUG
            // Smoke-test hook: `simctl launch ... -showAnalysisBoard 1`.
            if UserDefaults.standard.bool(forKey: "showAnalysisBoard") {
                analysisSeed = AnalysisSeed(
                    fen: PositionFENSerializer.fen(from: training.sessionState.session.board)
                )
            }
            #endif
        }
    }

    @ViewBuilder
    private func content(for screen: TacticsScreenViewModel) -> some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                    TacticsHeaderView(viewModel: screen.header)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                    ChessBoardView(
                        position: screen.board.position,
                        selectedSquare: screen.board.selectedSquare,
                        hintMove: screen.board.hintMove,
                        lastMove: screen.board.lastMove,
                        isFlipped: screen.board.isFlipped,
                        animation: screen.board.animation,
                        onSelect: screen.board.select
                    )
                    .frame(width: min(viewport.size.width, max(280, viewport.size.height - 238)))

                    HStack(alignment: .center, spacing: 12) {
                        RatingPanelView(viewModel: screen.rating)
                        Spacer(minLength: 8)
                        RoundProgressView(viewModel: screen.progress)
                    }
                    .padding(.horizontal, 4)

                    MoveControlsView(
                        viewModel: screen.controls,
                        onReviewCurrentPuzzle: {
                            reviewingPuzzle = screen.currentPuzzle
                        },
                        onOpenAnalysis: {
                            analysisSeed = AnalysisSeed(
                                fen: PositionFENSerializer.fen(from: screen.training.sessionState.session.board)
                            )
                        }
                    )

                    RoundActionsView(viewModel: screen.roundActions)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    let messageView = TacticsMessageArea(viewModel: screen.messages)
                    if messageView.hasMessage {
                        messageView
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                }
                }
            }
            .overlay {
                if let promotion = screen.promotion.pendingPromotion {
                    PromotionPickerView(viewModel: screen.promotion, promotion: promotion)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(String(localized: "app.name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHowToPlay = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(String(localized: "settings.how_to_play"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "tactics.settings"))
                }
            }
            .popover(isPresented: $showingHowToPlay) {
                HowToPlayView()
                    .presentationDetents([.medium, .large])
                    .frame(minWidth: 320, minHeight: 240)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $reviewingPuzzle) { puzzle in
                NavigationStack {
                    ReviewPuzzleView(puzzle: puzzle)
                }
            }
            .sheet(item: $analysisSeed) { seed in
                NavigationStack {
                    AnalysisScreenView(seedFEN: seed.fen)
                }
                .presentationDetents([.large])
            }
        }
    }

}

#Preview {
    TacticsView()
        .environment(AppDependencies.preview())
}
