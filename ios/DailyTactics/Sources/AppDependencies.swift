import Foundation
import Observation
import PuzzleKit
import TacticsData

/// The composition root: every object the features need, constructed once per
/// process and injected through the environment. No feature constructs a store
/// or reads a global.
@MainActor
@Observable
final class AppDependencies {
    let data: any PuzzleDataRepositories
    let importer: any LibraryImporting
    let batch: BatchTracker
    let difficulty: DifficultyModeStore
    let userRating: UserRatingStore
    let libraryState: LibraryStateStore
    let pacing: TacticsPacing

    init(
        data: any PuzzleDataRepositories,
        importer: any LibraryImporting,
        batch: BatchTracker,
        difficulty: DifficultyModeStore,
        userRating: UserRatingStore,
        libraryState: LibraryStateStore,
        pacing: TacticsPacing
    ) {
        self.data = data
        self.importer = importer
        self.batch = batch
        self.difficulty = difficulty
        self.userRating = userRating
        self.libraryState = libraryState
        self.pacing = pacing
    }

    /// The real app: on-disk store, standard defaults, wall clock.
    static func live() -> AppDependencies {
        let repositories = SwiftDataRepositories(inMemory: false)
        return AppDependencies(
            data: repositories,
            importer: PuzzleLibraryImporter(context: repositories.context),
            batch: BatchTracker(state: UserDefaultsBatchStateStore()),
            difficulty: DifficultyModeStore(),
            userRating: UserRatingStore(),
            libraryState: LibraryStateStore(),
            pacing: TacticsPacing()
        )
    }

    /// Previews and tests: in-memory store, isolated defaults.
    static func preview() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        let repositories = SwiftDataRepositories(container: ModelContainerFactory.makeInMemory())
        return AppDependencies(
            data: repositories,
            importer: PuzzleLibraryImporter(context: repositories.context),
            batch: BatchTracker(state: UserDefaultsBatchStateStore(defaults: defaults)),
            difficulty: DifficultyModeStore(defaults: defaults),
            userRating: UserRatingStore(defaults: defaults),
            libraryState: LibraryStateStore(defaults: defaults),
            pacing: TacticsPacing()
        )
    }
}
