import SwiftUI
import PuzzleKit
import SwiftData
import Charts
import TacticsData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @State private var difficulty = DifficultyMode.medium
    @State private var showingHowToPlay = false
    @State private var snapshots: [RatingSample] = []
    @State private var libraryChunk = 0
    @State private var libraryCount = 0
    #if DEBUG
    @State private var debugNotice: String?
    @State private var showingResetAllConfirm = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                ratingTrendSection

                Section {
                    Picker(String(localized: "settings.difficulty"), selection: $difficulty) {
                        ForEach(DifficultyMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                        }
                    }
                    .onChange(of: difficulty) { _, value in
                        dependencies.difficulty.set(value)
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text(String(localized: "settings.library_section"))
                } footer: {
                    Text(String(
                        format: NSLocalizedString("settings.library_status", comment: "Library chunk and puzzle count"),
                        libraryChunk, libraryCount
                    ))
                }

                #if DEBUG
                Section {
                    Button(String(localized: "debug.drain_pool")) {
                        drainUntriedPool()
                    }
                    Button(String(localized: "debug.reset_all"), role: .destructive) {
                        showingResetAllConfirm = true
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHowToPlay = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(String(localized: "settings.how_to_play"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            #if DEBUG
            .alert(
                String(localized: "debug.reset_all_confirm_title"),
                isPresented: $showingResetAllConfirm
            ) {
                Button(String(localized: "debug.reset_all"), role: .destructive) {
                    resetToInitialState()
                }
                Button(String(localized: "common.cancel"), role: .cancel) { }
            } message: {
                Text(String(localized: "debug.reset_all_confirm"))
            }
            .alert(
                String(localized: "debug.notice_title"),
                isPresented: Binding(get: { debugNotice != nil }, set: { if !$0 { debugNotice = nil } })
            ) {
                Button(String(localized: "common.done"), role: .cancel) { }
            } message: {
                Text(debugNotice ?? "")
            }
            #endif
            .alert(String(localized: "settings.how_to_play"), isPresented: $showingHowToPlay) {
                Button(String(localized: "common.got_it"), role: .cancel) { }
            } message: {
                Text(String(localized: "settings.how_to_play_body"))
            }
            .task {
                snapshots = dependencies.data.ratingHistory()
                difficulty = dependencies.difficulty.current
                libraryChunk = dependencies.sequenceStore.current
                libraryCount = dependencies.data.allPuzzles().count
            }
        }
    }

    #if DEBUG
    /// Back to first-launch state: every SwiftData row and every stored
    /// preference gone. Clearing the import gate re-routes RootView to the
    /// loading screen, which re-imports the bundled chunk.
    private func resetToInitialState() {
        dependencies.data.deleteAllData()
        AppPreferences.wipeAll()
    }

    /// Marks every library puzzle as attempted so the untried pool drops to
    /// zero; the next batch boundary then exercises the real download path.
    /// Note: this freezes rating updates for the drained library (no puzzle
    /// can be a first attempt anymore) — play still works via selection
    /// fallbacks. Reset by reinstalling or waiting for new chunks.
    private func drainUntriedPool() {
        let ids = dependencies.data.allPuzzles().map(\.id)
        dependencies.data.markAttempted(ids)
        debugNotice = String(format: NSLocalizedString("debug.drained", comment: "Pool drained notice"), ids.count)
    }
    #endif

    // MARK: - Rating trend

    /// One point per completed batch. Single series: the section title names
    /// it, so no legend; the line uses the app accent, which iOS keeps
    /// legible in both appearances.
    private var ratingTrendSection: some View {
        Section {
            if snapshots.isEmpty {
                Text(String(localized: "settings.rating_trend_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Chart(snapshots) { snapshot in
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
                .chartYScale(domain: ratingDomain)
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
                .accessibilityValue(trendAccessibilitySummary)
            }
        } header: {
            HStack {
                Text(String(localized: "settings.rating_trend"))
                Spacer()
                Text("\(currentRating)")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if let delta = trendDelta {
                Text(String(
                    format: NSLocalizedString("settings.rating_trend_delta", comment: "Change since the first snapshot"),
                    delta
                ))
            }
        }
    }

    private var currentRating: Int {
        snapshots.last?.rating ?? dependencies.userRating.rating
    }

    /// Rating floor/ceiling with padding so the line never touches the frame.
    private var ratingDomain: ClosedRange<Int> {
        let values = snapshots.map(\.rating)
        let lo = values.min() ?? 1500
        let hi = values.max() ?? 1500
        let pad = max(25, (hi - lo) / 4)
        return (lo - pad)...(hi + pad)
    }

    private var trendDelta: Int? {
        guard let first = snapshots.first?.rating, let last = snapshots.last?.rating,
              snapshots.count > 1
        else { return nil }
        return last - first
    }

    private var trendAccessibilitySummary: String {
        guard let first = snapshots.first, let last = snapshots.last else { return "" }
        return "\(first.rating) → \(last.rating)"
    }
}
