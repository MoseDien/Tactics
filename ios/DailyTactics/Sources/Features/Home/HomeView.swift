import SwiftUI
import PuzzleKit

/// The root screen: the current-round card (Continue / New round) plus the
/// history, favorites, and settings entries. The training board lives one
/// push away and only ever shows the active batch.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(TacticsScreenViewModel.self) private var screen
    @State private var model: HomeViewModel?
    @State private var isShowingTraining = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    ScrollView {
                        VStack(spacing: 16) {
                            AppWordmark(fontSize: 32)
                                .padding(.top, 8)
                            roundCard(for: model)
                            entriesCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "app.name"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingTraining) {
                TacticsView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: .settings(dependencies: dependencies))
        }
        .task {
            // Attached outside the `if let`, matching SettingsView: the card
            // only renders once the model exists.
            if model == nil {
                model = HomeViewModel(training: screen.training)
            }
        }
    }

    // MARK: - Round card

    private func roundCard(for model: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: model.isReviewingRound ? "home.round_status_review" : "home.round_status_progress"))
                    .font(.title3.bold())
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(localized: "tactics.rating"))
                        .foregroundStyle(.secondary)
                    Text("\(model.userRating)")
                        .monospacedDigit()
                }
                .font(.subheadline)
            }

            HStack(spacing: 12) {
                PuzzleResultRow(
                    outcomes: model.outcomes,
                    currentIndex: model.isReviewingRound ? nil : model.puzzleNumber - 1
                )
                Spacer()
                Text(String(
                    format: NSLocalizedString("tactics.puzzle_progress", comment: "Puzzle position in round"),
                    model.puzzleNumber,
                    model.puzzleCount
                ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if !model.isNewRoundAvailable, let unlock = model.nextRoundUnlockDescription {
                Label(unlock, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    isShowingTraining = true
                } label: {
                    Text(String(localized: model.isReviewingRound ? "home.continue_review" : "home.continue_training"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(String(localized: model.isReviewingRound ? "home.round_status_review" : "home.round_status_progress"))

                NextRoundButton(viewModel: screen.roundActions) {
                    isShowingTraining = true
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Feature entries

    private var entriesCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                HistoryView()
            } label: {
                entryLabel(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
            }
            Divider().padding(.leading, 46)
            NavigationLink {
                FavoritesView()
            } label: {
                entryLabel(String(localized: "settings.favorites"), systemImage: "heart")
            }
            Divider().padding(.leading, 46)
            Button {
                showingSettings = true
            } label: {
                entryLabel(String(localized: "settings.title"), systemImage: "gearshape")
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private func entryLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// Starts the next round once its window opens; gray and disabled inside
/// the window, with the unlock time shown on the card above.
struct NextRoundButton: View {
    let viewModel: TacticsRoundActionsViewModel
    var onStart: (() -> Void)? = nil

    var body: some View {
        Button {
            viewModel.startNextRound()
            onStart?()
        } label: {
            Text(String(localized: "tactics.next_round"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isNewRoundAvailable ? .accentColor : Color.gray)
        .disabled(!viewModel.isNewRoundAvailable)
        .accessibilityHint(viewModel.isNewRoundAvailable
            ? String(localized: "tactics.next_round_ready_hint")
            : String(localized: "tactics.next_round_wait_hint"))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    let screen = TacticsScreenViewModel(
        training: TacticsTrainingStore(
            dependencies: dependencies,
            dailyPuzzleCount: RoundPolicy.puzzleCount
        )
    )
    return HomeView()
        .environment(dependencies)
        .environment(screen)
}
