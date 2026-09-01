import SwiftUI
import PuzzleKit
import SwiftData
import Charts

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var difficulty = DifficultyModeStore.current
    @State private var showingHowToPlay = false
    @State private var snapshots: [RatingSnapshot] = []

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
                        DifficultyModeStore.set(value)
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(String(localized: "settings.history_footer"))
                }
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
            .alert(String(localized: "settings.how_to_play"), isPresented: $showingHowToPlay) {
                Button(String(localized: "common.got_it"), role: .cancel) { }
            } message: {
                Text(String(localized: "settings.how_to_play_body"))
            }
            .task {
                snapshots = PuzzleProgressStore(context: modelContext).ratingHistory()
            }
        }
    }

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
        snapshots.last?.rating ?? UserRatingStore().rating
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
