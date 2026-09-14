import SwiftUI
import PuzzleKit
import SwiftData
import Charts
import TacticsData

/// The settings form: pure layout and binding. All state and actions live in
/// `SettingsViewModel`.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        NavigationStack {
            if let viewModel {
                form(for: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            // Attached outside the `if let`: the form (and its own modifiers)
            // only render once the model exists, so this must live here.
            if viewModel == nil {
                let built = SettingsViewModel(dependencies: dependencies)
                built.load()
                viewModel = built
            }
        }
    }

    @ViewBuilder
    private func form(for model: SettingsViewModel) -> some View {
        Form {
            ratingTrendSection(for: model)

            Section {
                Picker(String(localized: "settings.difficulty"), selection: Binding(
                    get: { model.difficulty },
                    set: { model.difficulty = $0; model.setDifficulty($0) }
                )) {
                    ForEach(DifficultyMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                    }
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    FavoritesView()
                } label: {
                    Label(String(localized: "settings.favorites"), systemImage: "heart")
                }

                Button {
                    model.downloadMorePuzzlesTapped()
                } label: {
                    Label {
                        HStack(spacing: 8) {
                            Text(String(localized: "settings.download_more_puzzles"))
                            if model.isDownloadingMorePuzzles {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.secondary)
                                    .opacity(0.65)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .disabled(!model.isEligibleForManualDownload)
                .foregroundStyle(model.isEligibleForManualDownload ? Color.primary : Color.secondary)
                .popover(
                    isPresented: Binding(
                        get: { model.downloadMorePuzzlesNotice != nil },
                        set: { if !$0 { model.downloadMorePuzzlesNotice = nil } }
                    ),
                    arrowEdge: .top
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.download_more_puzzles_unavailable_title"))
                            .font(.headline)
                        Text(model.downloadMorePuzzlesNotice ?? "")
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            } header: {
                Text(String(localized: "settings.library_section"))
            } footer: {
                Text(String(
                    format: NSLocalizedString("settings.library_status", comment: "Library chunk and puzzle count"),
                    model.libraryChunk, model.libraryCount, model.untriedPuzzleCount
                ))
            }

            Section {
                Link(destination: URL(string: "mailto:beldailytactics@gmail.com")!) {
                    Label {
                        HStack {
                            Text(String(localized: "settings.contact"))
                            Spacer()
                            Text("beldailytactics@gmail.com")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } icon: {
                        Image(systemName: "envelope")
                    }
                }
                .contextMenu {
                    // Long-press copy for anyone who'd rather not open Mail.
                    Button {
                        UIPasteboard.general.string = "beldailytactics@gmail.com"
                    } label: {
                        Label(String(localized: "settings.contact_copy"), systemImage: "doc.on.doc")
                    }
                }
            } header: {
                Text(String(localized: "settings.more_section"))
            }

            #if DEBUG
            Section {
                Picker(String(localized: "debug.round_duration"), selection: Binding(
                    get: { model.roundDuration },
                    set: { model.roundDuration = $0; model.setRoundDuration($0) }
                )) {
                    ForEach(SettingsViewModel.debugRoundDurations, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(width: .abbreviated)))
                            .tag(seconds)
                    }
                }
                Button(String(localized: "debug.drain_pool")) {
                    model.drainUntriedPool()
                }
                Button(String(localized: "debug.reset_all"), role: .destructive) {
                    model.showingResetAllConfirm = true
                }
            } header: {
                Text(String(localized: "debug.section"))
            } footer: {
                Text(String(localized: "debug.footer"))
            }
            #endif
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.done")) { dismiss() }
            }
        }
        #if DEBUG
        .alert(
            String(localized: "debug.reset_all_confirm_title"),
            isPresented: Binding(
                get: { model.showingResetAllConfirm },
                set: { model.showingResetAllConfirm = $0 }
            )
        ) {
            Button(String(localized: "debug.reset_all"), role: .destructive) {
                model.resetToInitialState()
            }
            Button(String(localized: "common.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "debug.reset_all_confirm"))
        }
        .alert(
            String(localized: "debug.notice_title"),
            isPresented: Binding(
                get: { model.debugNotice != nil },
                set: { if !$0 { model.debugNotice = nil } }
            )
        ) {
            Button(String(localized: "common.done"), role: .cancel) { }
        } message: {
            Text(model.debugNotice ?? "")
        }
        #endif
    }

    // MARK: - Rating trend

    /// One point per completed round. Single series: the section title names
    /// it, so no legend; the line uses the app accent, which iOS keeps
    /// legible in both appearances.
    private func ratingTrendSection(for viewModel: SettingsViewModel) -> some View {
        Section {
            if viewModel.snapshots.isEmpty {
                Text(String(localized: "settings.rating_trend_empty"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Chart(viewModel.snapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.recordedAt),
                        y: .value("Rating", snapshot.rating)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", snapshot.recordedAt),
                        y: .value("Rating", snapshot.rating)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
                }
                .chartYScale(domain: viewModel.ratingDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
                .accessibilityLabel(String(localized: "settings.rating_trend"))
                .accessibilityValue(viewModel.trendAccessibilitySummary)
            }
        } header: {
            HStack {
                Text(String(localized: "settings.rating_trend"))
                Spacer()
                Text("\(viewModel.currentRating)")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if let delta = viewModel.trendDelta {
                Text(String(
                    format: NSLocalizedString("settings.rating_trend_delta", comment: "Change since the first snapshot"),
                    delta
                ))
            }
        }
    }
}
