import ComposableArchitecture
import Foundation
import PuzzleKit

/// The settings form: library status, difficulty, rating trend, chunked
/// downloads, and (Debug) the developer tools. Behavior mirrors the former
/// `SettingsViewModel` exactly; the view is pure layout over the store.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var difficulty: DifficultyMode = .medium
        var snapshots: [RatingSample] = []
        /// Fetched on load (the UserDefaults scalar while no snapshot exists).
        var currentRating = 1000
        var status = LibraryStatusClient.Status()
        var isDownloading = false
        var downloadNotice: String?

        /// Manual download stays available until the untried pool reaches this
        /// size; each tap fetches one chunk toward it.
        static let untriedPoolCapacity = 3000

        /// Low untried pool AND chunks left to fetch (the 404 latch kills it).
        var isEligibleForManualDownload: Bool {
            status.untriedCount < Self.untriedPoolCapacity && !status.noMoreChunks
        }

        #if DEBUG
        var debugNotice: String?
        var showingResetAllConfirm = false
        var roundDuration: TimeInterval = RoundPolicy.roundDuration

        /// Debug round-length options: 5 minutes through 8 hours.
        static let debugRoundDurations: [TimeInterval] = [
            5 * 60, 15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600,
        ]
        #endif

        // MARK: Rating trend derivations (chart math, unchanged)

        /// Padded so the line never touches the frame.
        var ratingDomain: ClosedRange<Int> {
            let values = snapshots.map(\.rating)
            let lo = values.min() ?? 1000
            let hi = values.max() ?? 1000
            let pad = max(25, (hi - lo) / 4)
            return (lo - pad)...(hi + pad)
        }

        /// The X axis spans at least one month (data centered inside the
        /// window), so a young history doesn't stretch a couple of days
        /// across the width.
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

    enum Action: BindableAction, Equatable {
        case onAppear
        case loaded(
            snapshots: [RatingSample],
            currentRating: Int,
            difficulty: DifficultyMode,
            status: LibraryStatusClient.Status
        )
        case downloadTapped
        case downloadFinished(ProvisionOutcome)
        case statusRefreshed(LibraryStatusClient.Status)
        case noticeDismissed
        case binding(BindingAction<State>)

        #if DEBUG
        case debugRoundDurationLoaded(TimeInterval)
        case drainPoolTapped
        case poolDrained(count: Int)
        case resetAllTapped
        case resetAllConfirmed
        case debugNoticeDismissed
        #endif
    }

    @Dependency(\.difficultyClient) var difficultyClient
    @Dependency(\.ratingHistoryClient) var ratingHistoryClient
    @Dependency(\.libraryStatusClient) var libraryStatusClient
    @Dependency(\.provisioningClient) var provisioningClient
    #if DEBUG
    @Dependency(\.settingsDebugClient) var settingsDebugClient
    #endif

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.loaded(
                        snapshots: ratingHistoryClient.snapshots(),
                        currentRating: ratingHistoryClient.currentRating(),
                        difficulty: difficultyClient.current(),
                        status: libraryStatusClient.status()
                    ))
                    #if DEBUG
                    await send(.debugRoundDurationLoaded(settingsDebugClient.roundDuration()))
                    #endif
                }

            case let .loaded(snapshots, currentRating, difficulty, status):
                state.snapshots = snapshots
                state.currentRating = currentRating
                state.difficulty = difficulty
                state.status = status
                return .none

            case .downloadTapped:
                guard !state.isDownloading else { return .none }
                guard state.isEligibleForManualDownload else {
                    state.downloadNotice = String(
                        localized: "settings.download_more_puzzles_unavailable_message"
                    )
                    return .none
                }
                state.isDownloading = true
                return .run { send in
                    await send(.downloadFinished(
                        provisioningClient.ensureAvailable(minimum: State.untriedPoolCapacity)
                    ))
                }

            case .downloadFinished:
                // The outcome is ignored — download failures fall back
                // silently; the library counts refresh either way.
                state.isDownloading = false
                return .run { send in
                    await send(.statusRefreshed(libraryStatusClient.status()))
                }

            case let .statusRefreshed(status):
                state.status = status
                return .none

            case .noticeDismissed:
                state.downloadNotice = nil
                return .none

            case .binding(\.difficulty):
                let mode = state.difficulty
                return .run { _ in await difficultyClient.set(mode) }

            #if DEBUG
            case .binding(\.roundDuration):
                let seconds = state.roundDuration
                return .run { _ in await settingsDebugClient.setRoundDuration(seconds) }

            case let .debugRoundDurationLoaded(seconds):
                state.roundDuration = seconds
                return .none

            case .drainPoolTapped:
                return .run { send in
                    await send(.poolDrained(count: settingsDebugClient.drainUntriedPool()))
                }

            case let .poolDrained(count):
                state.debugNotice = String(
                    format: NSLocalizedString("debug.drained", comment: "Pool drained notice"),
                    count
                )
                return .none

            case .resetAllTapped:
                state.showingResetAllConfirm = true
                return .none

            case .resetAllConfirmed:
                state.showingResetAllConfirm = false
                return .run { _ in await settingsDebugClient.resetAll() }

            case .debugNoticeDismissed:
                state.debugNotice = nil
                return .none
            #endif

            case .binding:
                return .none
            }
        }
    }
}
