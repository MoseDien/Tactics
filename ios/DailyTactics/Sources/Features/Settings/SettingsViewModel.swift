import Foundation
import PuzzleKit
import TacticsData

/// View model for the Settings screen: owns every piece of mutable state the
/// form drives (difficulty, library status, downloads, debug tools, the
/// rating-trend chart data) so the view stays pure layout and binding.
@MainActor
@Observable
final class SettingsViewModel {
    let dependencies: AppDependencies

    // MARK: Form state

    var difficulty = DifficultyMode.medium
    /// One snapshot per completed round; feeds the trend chart.
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

    /// Loads everything the form shows; call once on appear.
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

    /// Download conditions: the untried pool must be low AND the remote must
    /// still have unpublished chunks left (a 404 latch kills it for the
    /// session). Anything else grays the button out.
    var isEligibleForManualDownload: Bool {
        untriedPuzzleCount < 50 && !dependencies.sequenceStore.noMoreChunks
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
        _ = await dependencies.provisioner.ensureRoundAvailable(minimum: 50)
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
    /// Debug-only: applies a picked round length and recomputes the running
    /// window (restore = refresh + re-watch) so the new length bites now.
    func setRoundDuration(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: AppPreferences.roundDuration)
        dependencies.round.restore()
    }

    /// Back to first-launch state: every SwiftData row and every stored
    /// preference gone. Clearing the import gate re-routes RootView to the
    /// loading screen, which re-imports the bundled chunk.
    func resetToInitialState() {
        dependencies.data.deleteAllData()
        AppPreferences.wipeAll()
    }

    /// Marks every library puzzle as attempted so the untried pool drops to
    /// zero; the next round boundary then exercises the real download path.
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

    /// Rating floor/ceiling with padding so the line never touches the frame.
    var ratingDomain: ClosedRange<Int> {
        let values = snapshots.map(\.rating)
        let lo = values.min() ?? 1000
        let hi = values.max() ?? 1000
        let pad = max(25, (hi - lo) / 4)
        return (lo - pad)...(hi + pad)
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
