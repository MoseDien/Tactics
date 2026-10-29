import ComposableArchitecture
import Dependencies
import PuzzleKit
import XCTest
@testable import DailyTactics

/// Settings feature behavior, asserted action-by-action with TestStore —
/// no polling, no real repositories. Fakes are plain closures over small
/// recorders; any endpoint a test forgets to stub fails loudly.
@MainActor
final class SettingsFeatureTests: XCTestCase {

    // MARK: - Load

    func testOnAppearLoadsStatusSnapshotsAndDifficulty() async {
        let snapshots = [
            RatingSample(id: UUID(), recordedAt: Date(timeIntervalSince1970: 100), rating: 1000),
            RatingSample(id: UUID(), recordedAt: Date(timeIntervalSince1970: 200), rating: 1012),
        ]
        let status = LibraryStatusClient.Status(
            chunk: 2, puzzleCount: 2000, untriedCount: 900, noMoreChunks: false
        )

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.ratingHistoryClient.snapshots = { snapshots }
            $0.ratingHistoryClient.currentRating = { 1012 }
            $0.difficultyClient.current = { .hard }
            $0.libraryStatusClient.status = { status }
            $0.settingsDebugClient.roundDuration = { 900 }
        }

        await store.send(.onAppear)
        await store.receive(
            .loaded(snapshots: snapshots, currentRating: 1012, difficulty: .hard, status: status)
        ) {
            $0.snapshots = snapshots
            $0.currentRating = 1012
            $0.difficulty = .hard
            $0.status = status
        }
        await store.receive(.debugRoundDurationLoaded(900)) {
            $0.roundDuration = 900
        }
    }

    /// No snapshots yet: the header rating falls back to the UserDefaults
    /// scalar carried by the same load.
    func testCurrentRatingFallsBackWhenNoSnapshotsExist() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.ratingHistoryClient.snapshots = { [] }
            $0.ratingHistoryClient.currentRating = { 1000 }
            $0.difficultyClient.current = { .medium }
            $0.libraryStatusClient.status = { .init(chunk: 1, puzzleCount: 1000, untriedCount: 1000) }
            $0.settingsDebugClient.roundDuration = { RoundPolicy.roundDuration }
        }

        await store.send(.onAppear)
        let expectedStatus = LibraryStatusClient.Status(chunk: 1, puzzleCount: 1000, untriedCount: 1000)
        await store.receive(
            .loaded(snapshots: [], currentRating: 1000, difficulty: .medium, status: expectedStatus)
        ) {
            $0.status = expectedStatus
        }
        // Round-trips the current default (300s in Debug): no state change.
        await store.receive(.debugRoundDurationLoaded(RoundPolicy.roundDuration))
    }

    // MARK: - Rating trend derivations (pure State)

    func testRatingDomainPadsExtremes() {
        var state = SettingsFeature.State()
        state.snapshots = [
            RatingSample(id: UUID(), recordedAt: Date(), rating: 900),
            RatingSample(id: UUID(), recordedAt: Date(), rating: 1000),
            RatingSample(id: UUID(), recordedAt: Date(), rating: 1100),
        ]
        XCTAssertEqual(state.ratingDomain, 850...1150, "pad is a quarter of the range")
    }

    func testRatingDomainDefaultsWithoutSnapshots() {
        XCTAssertEqual(SettingsFeature.State().ratingDomain, 975...1025)
    }

    func testRatingDateDomainSpansAtLeastOneMonth() {
        var state = SettingsFeature.State()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let span: TimeInterval = 60 * 60 * 24
        state.snapshots = [
            RatingSample(id: UUID(), recordedAt: start, rating: 1000),
            RatingSample(id: UUID(), recordedAt: start.addingTimeInterval(span), rating: 1005),
        ]
        let domain = state.ratingDateDomain
        let oneMonth: TimeInterval = 30 * 24 * 60 * 60
        let pad = (oneMonth - span) / 2
        XCTAssertEqual(domain.lowerBound, start.addingTimeInterval(-pad))
        XCTAssertEqual(domain.upperBound, start.addingTimeInterval(span + pad))
        XCTAssertEqual(
            domain.upperBound.timeIntervalSince(domain.lowerBound),
            oneMonth,
            "a young history is padded to one month, centered"
        )
    }

    func testTrendDeltaNilForFewerThanTwoSnapshots() {
        var state = SettingsFeature.State()
        state.snapshots = [RatingSample(id: UUID(), recordedAt: Date(), rating: 1000)]
        XCTAssertNil(state.trendDelta)
        state.snapshots = [
            RatingSample(id: UUID(), recordedAt: Date(), rating: 1000),
            RatingSample(id: UUID(), recordedAt: Date(), rating: 1032),
        ]
        XCTAssertEqual(state.trendDelta, 32)
    }

    // MARK: - Manual download

    func testDownloadTappedFetchesChunkAndRefreshesStatus() async {
        let refreshed = LibraryStatusClient.Status(
            chunk: 2, puzzleCount: 2000, untriedCount: 2000, noMoreChunks: false
        )

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.provisioningClient.ensureAvailable = { minimum in
                XCTAssertEqual(minimum, SettingsFeature.State.untriedPoolCapacity)
                return .added(count: 1000)
            }
            $0.libraryStatusClient.status = { refreshed }
        }

        await store.send(.downloadTapped) {
            $0.isDownloading = true
        }
        await store.receive(.downloadFinished(.added(count: 1000))) {
            $0.isDownloading = false
        }
        await store.receive(.statusRefreshed(refreshed)) {
            $0.status = refreshed
        }
    }

    func testDownloadTappedAtThresholdShowsPopoverNotice() async {
        var initial = SettingsFeature.State()
        initial.status = LibraryStatusClient.Status(
            chunk: 4, puzzleCount: 4000, untriedCount: 3000, noMoreChunks: false
        )

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.provisioningClient.ensureAvailable = { _ in
                XCTFail("the threshold guard must not fetch")
                return .skipped
            }
        }

        await store.send(.downloadTapped) {
            $0.downloadNotice = String(
                localized: "settings.download_more_puzzles_unavailable_message"
            )
        }
    }

    func testDownloadTappedBlockedAfterChunkLatching() async {
        var initial = SettingsFeature.State()
        initial.status = LibraryStatusClient.Status(
            chunk: 9, puzzleCount: 1000, untriedCount: 10, noMoreChunks: true
        )

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }

        await store.send(.downloadTapped) {
            $0.downloadNotice = String(
                localized: "settings.download_more_puzzles_unavailable_message"
            )
        }
    }

    func testDownloadTappedWhileInFlightIsIgnored() async {
        var initial = SettingsFeature.State()
        initial.isDownloading = true

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.provisioningClient.ensureAvailable = { _ in
                XCTFail("an in-flight download must not start a second fetch")
                return .skipped
            }
        }

        await store.send(.downloadTapped)
    }

    func testNoticeDismissedClearsNotice() async {
        var initial = SettingsFeature.State()
        initial.downloadNotice = "notice"

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }

        await store.send(.noticeDismissed) {
            $0.downloadNotice = nil
        }
    }

    // MARK: - Bindings

    func testDifficultyBindingCallsSetOnClient() async {
        let recorded = LockIsolated<[DifficultyMode]>([])

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.difficultyClient.set = { mode in
                recorded.withValue { $0.append(mode) }
            }
        }

        await store.send(.binding(.set(\.difficulty, DifficultyMode.hard))) {
            $0.difficulty = .hard
        }
        XCTAssertEqual(recorded.value, [.hard])
    }

    // MARK: - Debug tools

    func testDebugRoundDurationBindingWrites() async {
        let recorded = LockIsolated<[TimeInterval]>([])

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.settingsDebugClient.setRoundDuration = { seconds in
                recorded.withValue { $0.append(seconds) }
            }
        }

        await store.send(.binding(.set(\.roundDuration, 900))) {
            $0.roundDuration = 900
        }
        XCTAssertEqual(recorded.value, [900])
    }

    func testDrainPoolTappedShowsDrainedCountNotice() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.settingsDebugClient.drainUntriedPool = { 1000 }
        }

        await store.send(.drainPoolTapped)
        await store.receive(.poolDrained(count: 1000)) {
            $0.debugNotice = String(
                format: NSLocalizedString("debug.drained", comment: "Pool drained notice"),
                1000
            )
        }
    }

    func testResetAllTappedConfirmsThenWipes() async {
        let resetCount = LockIsolated(0)

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.settingsDebugClient.resetAll = {
                resetCount.withValue { $0 += 1 }
            }
        }

        await store.send(.resetAllTapped) {
            $0.showingResetAllConfirm = true
        }
        await store.send(.resetAllConfirmed) {
            $0.showingResetAllConfirm = false
        }
        XCTAssertEqual(resetCount.value, 1, "confirmation wipes exactly once")
    }
}
