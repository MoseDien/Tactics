import SwiftUI
import PuzzleKit
import Charts
import ComposableArchitecture
import TacticsData

/// The settings form: pure layout and bindings over the TCA store.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack {
            form
                .task { store.send(.onAppear) }
        }
    }

    private var form: some View {
        Form {
            ratingTrendSection

            Section {
                Picker(String(localized: "settings.difficulty"), selection: $store.difficulty) {
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
                    store.send(.downloadTapped)
                } label: {
                    Label {
                        HStack(spacing: 8) {
                            Text(String(localized: "settings.download_more_puzzles"))
                            if store.isDownloading {
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
                .disabled(!store.isEligibleForManualDownload)
                .foregroundStyle(store.isEligibleForManualDownload ? Color.primary : Color.secondary)
                .popover(
                    isPresented: Binding(
                        get: { store.downloadNotice != nil },
                        set: { if !$0 { store.send(.noticeDismissed) } }
                    ),
                    arrowEdge: .top
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.download_more_puzzles_unavailable_title"))
                            .font(.headline)
                        Text(store.downloadNotice ?? "")
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
                    store.status.chunk, store.status.puzzleCount, store.status.untriedCount
                ))
            }

            Section {
                NavigationLink {
                    AnalysisScreenView(seedFEN: Analysis.Position.startFEN)
                } label: {
                    Label(String(localized: "settings.free_board"), systemImage: "checkerboard.rectangle")
                }
            } header: {
                Text(String(localized: "settings.tools_section"))
            } footer: {
                Text(String(localized: "settings.free_board_description"))
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
                Picker(String(localized: "debug.round_duration"), selection: $store.roundDuration) {
                    ForEach(SettingsFeature.State.debugRoundDurations, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(width: .abbreviated)))
                            .tag(seconds)
                    }
                }
                Button(String(localized: "debug.drain_pool")) {
                    store.send(.drainPoolTapped)
                }
                Button(String(localized: "debug.reset_all"), role: .destructive) {
                    store.send(.resetAllTapped)
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
            isPresented: $store.showingResetAllConfirm
        ) {
            Button(String(localized: "debug.reset_all"), role: .destructive) {
                store.send(.resetAllConfirmed)
            }
            Button(String(localized: "common.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "debug.reset_all_confirm"))
        }
        .alert(
            String(localized: "debug.notice_title"),
            isPresented: Binding(
                get: { store.debugNotice != nil },
                set: { if !$0 { store.send(.debugNoticeDismissed) } }
            )
        ) {
            Button(String(localized: "common.done"), role: .cancel) { }
        } message: {
            Text(store.debugNotice ?? "")
        }
        #endif
    }

    // MARK: - Rating trend

    /// One point per completed round. Single series: the section title names
    /// it, so no legend; the line uses the app accent, which iOS keeps
    /// legible in both appearances.
    private var ratingTrendSection: some View {
        Section {
            if store.snapshots.isEmpty {
                Text(String(localized: "settings.rating_trend_empty"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Chart(store.snapshots) { snapshot in
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
                .chartYScale(domain: store.ratingDomain)
                .chartXScale(domain: store.ratingDateDomain)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
                .accessibilityLabel(String(localized: "settings.rating_trend"))
                .accessibilityValue(store.trendAccessibilitySummary)
            }
        } header: {
            HStack {
                Text(String(localized: "settings.rating_trend"))
                Spacer()
                Text("\(store.currentRating)")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if let delta = store.trendDelta {
                Text(String(
                    format: NSLocalizedString("settings.rating_trend_delta", comment: "Change since the first snapshot"),
                    delta
                ))
            }
        }
    }
}

#Preview {
    SettingsView(store: .settings(dependencies: AppDependencies.preview()))
}
