import SwiftUI
import SwiftData

struct RatingAssessmentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TacticsViewModel
    @State private var index = 0
    @State private var solvedCount = 0
    @State private var failedCount = 0
    @State private var finished = false
    @State private var assessmentMessage: String?
    @State private var results: [Bool?]
    @State private var showCompletionAlert = false
    @State private var isImporting = false
    @State private var importProgress = 0.0
    private let puzzles: [Puzzle]

    init(puzzles: [Puzzle]) {
        self.puzzles = puzzles
        _viewModel = State(initialValue: TacticsViewModel(dataset: puzzles, batchSize: puzzles.count))
        _results = State(initialValue: Array(repeating: nil, count: puzzles.count))
    }

    var body: some View {
        if isImporting {
            importingView
        } else if finished {
            completionView
        } else {
            NavigationStack {
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("BASELINE RATING")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text("Solve \(puzzles.count) puzzles of different difficulty")
                            .font(.headline)
                        Text("Puzzle \(index + 1) of \(puzzles.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.playerColor == .white ? "White" : "Black") to move")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 12)

                    ChessBoardView(
                        position: viewModel.displayedPosition,
                        selectedSquare: viewModel.selectedSquare,
                        hintMove: viewModel.hintMove,
                        lastMove: viewModel.lastMove,
                        isFlipped: viewModel.isBoardFlipped,
                        onSelect: viewModel.select
                    )
                    .frame(maxWidth: 420)

                    resultList

                    Text(assessmentMessage ?? viewModel.feedbackState.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .navigationTitle("Rating Assessment")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    viewModel.start()
                }
                .onChange(of: viewModel.state) { _, state in
                    switch state {
                    case .solved:
                        solvedCount += 1
                        results[index] = true
                        advanceAfterResult(message: "Correct — next puzzle")
                    case .incorrectMove:
                        failedCount += 1
                        results[index] = false
                        assessmentMessage = "Failed — moving to the next puzzle"
                        advanceAfterResult(message: nil)
                    default:
                        break
                    }
                }
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Baseline rating ready")
                .font(.title2.bold())
            Text("Your starting rating is \(baselineRating).")
                .font(.headline)
            Text("You can reassess this rating later from Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear {
            showCompletionAlert = true
        }
        .alert("Rating assessment complete", isPresented: $showCompletionAlert) {
            Button("Continue") {
                importLibraryAndContinue()
            }
        } message: {
            Text("Your baseline rating is \(baselineRating). You can reassess it later from Settings.")
        }
    }

    private var baselineRating: Int {
        let average = puzzles.compactMap(\.rating).reduce(0, +) / max(1, puzzles.compactMap(\.rating).count)
        let performanceAdjustment = Int((Double(solvedCount) / Double(max(1, puzzles.count)) - 0.5) * 400)
        return min(2400, max(400, average + performanceAdjustment))
    }

    private func finishAssessment() {
        finished = true
    }

    private var importingView: some View {
        VStack(spacing: 18) {
            ProgressView(value: importProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            Text("Preparing your puzzle library…")
                .font(.headline)
            Text("\(Int(importProgress * 100))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importLibraryAndContinue() {
        isImporting = true
        Task { @MainActor in
            await PuzzleLibraryImporter(context: modelContext).importBundled(for: baselineRating) { value in
                importProgress = value
            }
            RatingAssessmentStore(context: modelContext).complete(baselineRating: baselineRating)
            UserRatingStore().set(rating: baselineRating)
            isImporting = false
        }
    }

    private func advanceAfterResult(message: String?) {
        if let message {
            assessmentMessage = message
        }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            if index == puzzles.count - 1 {
                finishAssessment()
            } else {
                index += 1
                assessmentMessage = nil
                viewModel.nextPuzzle()
            }
        }
    }

    private var resultList: some View {
        PuzzleResultRow(outcomes: results.map { $0.map { $0 ? .correct : .wrong } })
    }
}

private extension TacticsFeedbackState {
    var message: String {
        switch self {
        case let .error(message): return message
        case let .instruction(message, _): return message
        case .opponentMoving: return "Opponent is moving…"
        case .opponentReply: return "Opponent's reply"
        case .incorrectMove: return "Not quite — try again."
        case .reviewing: return "Reviewing move"
        case .puzzleComplete, .trainingComplete: return "Puzzle complete!"
        }
    }
}
