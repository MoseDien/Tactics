import Foundation
import PuzzleKit
import TacticsData

/// Settings form state and actions; the view is pure layout.
@MainActor
@Observable
final class SettingsViewModel {
    let dependencies: AppDependencies

    // MARK: Form state

    var difficulty = DifficultyMode.medium
    var snapshots: [RatingSample] = []
    var libraryChunk = 0
    var libraryCount = 0
    var untriedPuzzleCount = 0
    var isDownloadingMorePuzzles = false
    var downloadMorePuzzlesNotice: String?

    #if DEBUG
    var debugNotice: String?
    var showingResetAllConfirm = false
    var roundDuration: TimeInterval = RoundPolicy.roundDuration

    /// Debug round-length options: 5 minutes through 8 hours.
    static let debugRoundDurations: [TimeInterval] = [
        5 * 60, 15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600,
    ]
    #endif

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() {
        snapshots = dependencies.data.ratingHistory()
        difficulty = dependencies.difficulty.current
        refreshLibraryStatus()
        #if DEBUG
        roundDuration = UserDefaults.standard.object(forKey: AppPreferences.roundDuration) == nil
            ? RoundPolicy.roundDuration
            : UserDefaults.standard.double(forKey: AppPreferences.roundDuration)
        #endif
    }

    func setDifficulty(_ value: DifficultyMode) {
        dependencies.difficulty.set(value)
    }

    // MARK: Library status & downloads

    /// Manual download stays available until the untried pool reaches this
    /// size; each tap fetches one chunk toward it.
    static let untriedPoolCapacity = 3000

    /// Low untried pool AND chunks left to fetch (404 latch kills it).
    var isEligibleForManualDownload: Bool {
        untriedPuzzleCount < Self.untriedPoolCapacity && !dependencies.sequenceStore.noMoreChunks
    }

    func downloadMorePuzzlesTapped() {
        guard !isDownloadingMorePuzzles else { return }
        guard isEligibleForManualDownload else {
            downloadMorePuzzlesNotice = String(localized: "settings.download_more_puzzles_unavailable_message")
            return
        }
        Task { await downloadMorePuzzles() }
    }

    private func downloadMorePuzzles() async {
        guard !isDownloadingMorePuzzles, isEligibleForManualDownload else { return }
        isDownloadingMorePuzzles = true
        _ = await dependencies.provisioner.ensureRoundAvailable(minimum: Self.untriedPoolCapacity)
        refreshLibraryStatus()
        isDownloadingMorePuzzles = false
    }

    private func refreshLibraryStatus() {
        let library = dependencies.data.allPuzzles()
        libraryChunk = dependencies.sequenceStore.current
        libraryCount = library.count
        untriedPuzzleCount = library.count - dependencies.data.attemptedIDs().count
    }

    // MARK: Debug tools

    #if DEBUG
    func setRoundDuration(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: AppPreferences.roundDuration)
        dependencies.round.restore()
    }

    /// First-launch state: wipes all rows and preferences; re-imports after.
    func resetToInitialState() {
        dependencies.data.deleteAllData()
        AppPreferences.wipeAll()
    }

    /// Empties the untried pool to exercise the download path.
    func drainUntriedPool() {
        let ids = dependencies.data.allPuzzles().map(\.id)
        dependencies.data.markAttempted(ids)
        debugNotice = String(format: NSLocalizedString("debug.drained", comment: "Pool drained notice"), ids.count)
    }
    #endif

    // MARK: Rating trend

    var currentRating: Int {
        snapshots.last?.rating ?? dependencies.userRating.rating
    }

    /// Padded so the line never touches the frame.
    var ratingDomain: ClosedRange<Int> {
        let values = snapshots.map(\.rating)
        let lo = values.min() ?? 1000
        let hi = values.max() ?? 1000
        let pad = max(25, (hi - lo) / 4)
        return (lo - pad)...(hi + pad)
    }

    /// The X axis spans at least one month (data centered inside the window),
    /// so a young history doesn't stretch a couple of days across the width.
    var ratingDateDomain: ClosedRange<Date> {
        let oneMonth: TimeInterval = 30 * 24 * 60 * 60
        let start = snapshots.first?.recordedAt ?? Date()
        let end = snapshots.last?.recordedAt ?? Date()
        let span = end.timeIntervalSince(start)
        guard span < oneMonth else { return start...end }
        let pad = (oneMonth - span) / 2
        return start.addingTimeInterval(-pad)...end.addingTimeInterval(pad)
    }

    var trendDelta: Int? {
        guard let first = snapshots.first?.rating, let last = snapshots.last?.rating,
              snapshots.count > 1
        else { return nil }
        return last - first
    }

    var trendAccessibilitySummary: String {
        guard let first = snapshots.first, let last = snapshots.last else { return "" }
        return "\(first.rating) → \(last.rating)"
    }
}
