import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import PuzzleKit
import TacticsData

// The seam between TCA and the app's instance-based composition root: each
// client fronts the one `AppDependencies` object, closed over per store (see
// `Store.settings(dependencies:)` below) — no liveValue registration, no
// second composition root, so the feature always talks to the same live
// RoundTracker/repositories every other screen uses.
//
// The macro-mandated closure defaults are placeholders only: every store gets
// its real implementation from `Store.settings(dependencies:)`.

// MARK: - Clients

@DependencyClient
struct DifficultyClient: Sendable {
    var current: @Sendable () async -> DifficultyMode = { .medium }
    var set: @Sendable (_ mode: DifficultyMode) async -> Void
}

@DependencyClient
struct RatingHistoryClient: Sendable {
    var snapshots: @Sendable () async -> [RatingSample] = { [] }
    /// The UserDefaults scalar — the fallback when no snapshot exists yet.
    var currentRating: @Sendable () async -> Int = { 1000 }
}

@DependencyClient
struct LibraryStatusClient: Sendable {
    struct Status: Equatable, Sendable {
        var chunk = 0
        var puzzleCount = 0
        var untriedCount = 0
        var noMoreChunks = false
    }

    var status: @Sendable () async -> Status = { .init() }
}

@DependencyClient
struct ProvisioningClient: Sendable {
    var ensureAvailable: @Sendable (_ minimum: Int) async -> ProvisionOutcome = { _ in .skipped }
}

#if DEBUG
/// Settings → Debug tools. Debug-only: the section is compiled out of
/// release builds together with this client.
@DependencyClient
struct SettingsDebugClient: Sendable {
    var roundDuration: @Sendable () async -> TimeInterval = { RoundPolicy.roundDuration }
    var setRoundDuration: @Sendable (_ seconds: TimeInterval) async -> Void
    /// Empties the untried pool to exercise the download path; returns the
    /// number of puzzles marked attempted.
    var drainUntriedPool: @Sendable () async -> Int = { 0 }
    /// Back-to-first-launch: wipes every row and preference.
    var resetAll: @Sendable () async -> Void
}
#endif

// MARK: - TestDependencyKey

// The macro-mandated closure defaults double as the unimplemented testValue:
// any endpoint a test forgets to override reports a failure when hit.
extension DifficultyClient: TestDependencyKey {
    static let testValue = DifficultyClient()
}

extension RatingHistoryClient: TestDependencyKey {
    static let testValue = RatingHistoryClient()
}

extension LibraryStatusClient: TestDependencyKey {
    static let testValue = LibraryStatusClient()
}

extension ProvisioningClient: TestDependencyKey {
    static let testValue = ProvisioningClient()
}

#if DEBUG
extension SettingsDebugClient: TestDependencyKey {
    static let testValue = SettingsDebugClient()
}
#endif

// MARK: - DependencyValues

extension DependencyValues {
    var difficultyClient: DifficultyClient {
        get { self[DifficultyClient.self] }
        set { self[DifficultyClient.self] = newValue }
    }

    var ratingHistoryClient: RatingHistoryClient {
        get { self[RatingHistoryClient.self] }
        set { self[RatingHistoryClient.self] = newValue }
    }

    var libraryStatusClient: LibraryStatusClient {
        get { self[LibraryStatusClient.self] }
        set { self[LibraryStatusClient.self] = newValue }
    }

    var provisioningClient: ProvisioningClient {
        get { self[ProvisioningClient.self] }
        set { self[ProvisioningClient.self] = newValue }
    }

    #if DEBUG
    var settingsDebugClient: SettingsDebugClient {
        get { self[SettingsDebugClient.self] }
        set { self[SettingsDebugClient.self] = newValue }
    }
    #endif
}

// MARK: - Live bridges

/// The repositories are non-Sendable MainActor objects, so every live
/// endpoint hops through these isolated helpers instead of touching the
/// stored properties from a detached closure.
@MainActor
private enum SettingsLive {
    static func difficulty(_ dependencies: AppDependencies) -> DifficultyMode {
        dependencies.difficulty.current
    }

    static func setDifficulty(_ dependencies: AppDependencies, to mode: DifficultyMode) {
        dependencies.difficulty.set(mode)
    }

    static func snapshots(_ dependencies: AppDependencies) -> [RatingSample] {
        dependencies.data.ratingHistory()
    }

    static func currentRating(_ dependencies: AppDependencies) -> Int {
        dependencies.userRating.rating
    }

    static func status(_ dependencies: AppDependencies) -> LibraryStatusClient.Status {
        let library = dependencies.data.allPuzzles()
        let attempted = dependencies.data.attemptedIDs()
        return LibraryStatusClient.Status(
            chunk: dependencies.sequenceStore.current,
            puzzleCount: library.count,
            untriedCount: library.count - attempted.count,
            noMoreChunks: dependencies.sequenceStore.noMoreChunks
        )
    }

    static func ensureAvailable(
        _ dependencies: AppDependencies, minimum: Int
    ) async -> ProvisionOutcome {
        await dependencies.provisioner.ensureRoundAvailable(minimum: minimum)
    }

    #if DEBUG
    static func restoreRoundWindow(_ dependencies: AppDependencies) {
        dependencies.round.restore()
    }

    static func drainUntriedPool(_ dependencies: AppDependencies) -> Int {
        let ids = dependencies.data.allPuzzles().map(\.id)
        dependencies.data.markAttempted(ids)
        return ids.count
    }

    static func resetAll(_ dependencies: AppDependencies) {
        dependencies.data.deleteAllData()
        AppPreferences.wipeAll()
    }
    #endif
}

private func liveDifficulty(_ dependencies: AppDependencies) -> DifficultyClient {
    DifficultyClient(
        current: { await SettingsLive.difficulty(dependencies) },
        set: { mode in await SettingsLive.setDifficulty(dependencies, to: mode) }
    )
}

private func liveRatingHistory(_ dependencies: AppDependencies) -> RatingHistoryClient {
    RatingHistoryClient(
        snapshots: { await SettingsLive.snapshots(dependencies) },
        currentRating: { await SettingsLive.currentRating(dependencies) }
    )
}

private func liveLibraryStatus(_ dependencies: AppDependencies) -> LibraryStatusClient {
    LibraryStatusClient(
        status: { await SettingsLive.status(dependencies) }
    )
}

private func liveProvisioning(_ dependencies: AppDependencies) -> ProvisioningClient {
    ProvisioningClient(
        ensureAvailable: { minimum in
            await SettingsLive.ensureAvailable(dependencies, minimum: minimum)
        }
    )
}

#if DEBUG
private func liveSettingsDebug(_ dependencies: AppDependencies) -> SettingsDebugClient {
    SettingsDebugClient(
        roundDuration: {
            UserDefaults.standard.object(forKey: AppPreferences.roundDuration) == nil
                ? RoundPolicy.roundDuration
                : UserDefaults.standard.double(forKey: AppPreferences.roundDuration)
        },
        setRoundDuration: { seconds in
            UserDefaults.standard.set(seconds, forKey: AppPreferences.roundDuration)
            await SettingsLive.restoreRoundWindow(dependencies)
        },
        drainUntriedPool: { await SettingsLive.drainUntriedPool(dependencies) },
        resetAll: { await SettingsLive.resetAll(dependencies) }
    )
}
#endif

// MARK: - Store factory

extension Store where State == SettingsFeature.State, Action == SettingsFeature.Action {
    /// The single sanctioned construction site for Settings stores. A store
    /// captures the dependency values present at initialization, so the
    /// `Store` itself must be created inside `withDependencies`.
    static func settings(dependencies: AppDependencies) -> Store<SettingsFeature.State, SettingsFeature.Action> {
        withDependencies {
            $0.difficultyClient = liveDifficulty(dependencies)
            $0.ratingHistoryClient = liveRatingHistory(dependencies)
            $0.libraryStatusClient = liveLibraryStatus(dependencies)
            $0.provisioningClient = liveProvisioning(dependencies)
            #if DEBUG
            $0.settingsDebugClient = liveSettingsDebug(dependencies)
            #endif
        } operation: {
            Store(initialState: SettingsFeature.State()) {
                SettingsFeature()
            }
        }
    }
}
