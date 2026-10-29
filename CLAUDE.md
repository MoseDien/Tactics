# DailyTactics contributor guide

## Mission

当前阶段只开发和维护 iOS 版本。Android 工程暂时冻结，待 iOS 完成后再恢复 Android 开发。

Maintain a small, offline iOS chess-tactics trainer. Prioritize a fast loop:
load a puzzle, play the correct line, receive feedback, review the line, and
move to the next puzzle.

Do not add backend services, accounts, social features, AI, multiplayer,
subscriptions, analytics, or cloud sync unless explicitly requested.
(The one sanctioned network behavior is chunked puzzle downloads: when the
untried pool can't fill a round, the next `puzzle-NNNN.json` is fetched from
the deployed catalog and imported; failures fall back silently.)

## Technology

- Swift 6, SwiftUI, Swift Concurrency
- iOS 17+
- Tuist 4.x is the source of truth for the Xcode project under `ios/`
- SwiftData only behind `Persistence` interfaces
- XCTest for domain and feature behavior
- The Composable Architecture (TCA 1.26.x) in the app target only, declared in
  `ios/Tuist/Package.swift` (installed with `tuist install`). The migration is
  pilot-first; evaluation, coexistence rules, and the phase plan live in
  [docs/TCA_MIGRATION_EVALUATION.md](docs/TCA_MIGRATION_EVALUATION.md).

Bundle ID: `com.dienbell.tactics`.

The current Daily Tactics, round, persistence, difficulty, promotion, and
localization rules are documented in
[docs/BUSINESS_LOGIC.md](docs/BUSINESS_LOGIC.md).

## Architecture

Tuist generates one project with four product targets; the dependency
direction is compiler-enforced and acyclic:

```text
DailyTactics (app)  → PuzzleKit, TacticsData
TacticsData         → PuzzleKit            (the only module importing SwiftData)
PuzzleKit           → ChessCore
```

```text
DailyTacticsApp
  ├── AppDependencies (composition root, injected via .environment)
  ├── RootView task builds the session-scoped TacticsTrainingStore /
  │   TacticsScreenViewModel after the import gate (injected via .environment)
  ├── RoundTracker / TacticsPacing (observable round window, injectable clock & pacing)
  ├── Features/Home         root screen: round card, Continue / New round,
  │                          history / favorites / settings entries
  ├── Features/Tactics      pushed training board: the active batch only
  ├── Features/Settings     difficulty, rating trend, history entry
  └── Features/Onboarding   first-launch library import
```

### ChessCore (`ios/ChessCore/`)

Pure, `Sendable` chess value types: pieces, colors, squares, UCI moves, FEN
parsing (placement, side to move, castling rights, en-passant target), board
application, and full legality validation (shape, check, pins, castling, en
passant, promotion). It must not import SwiftUI, SwiftData, or feature code.

### PuzzleKit (`ios/PuzzleKit/`)

Domain: `Puzzle`/`PuzzleSession` (Lichess move arrays start with the machine
setup move; review replay is deterministic), policies (`RatingPolicy`,
`RoundPolicy`/`RoundWindow`/`RoundLookup`, `RoundSelector` with injectable
shuffle), and the repository ports (`PuzzleLibraryRepository`, the chunked
delivery ports (`PuzzleChunkFetching`, `PuzzleProvisioning`),
`PuzzleProgressRepository`, `RoundHistoryRepository`, `RatingHistoryRepository`,
`BatchStateRepository`, `LibraryImporting`) — the seam a future remote API
plugs into behind the same signatures.

### TacticsData (`ios/TacticsData/`)

All persistence: the four SwiftData models (`PuzzleRecord`, `PuzzleProgress`,
`RoundHistory`, `RatingSnapshot`), the single `SwiftDataRepositories` adapter
implementing the data ports, `ModelContainerFactory`, `BundledPuzzleSource`
(the bundled `puzzle-0000.json` chunk lives in this framework's bundle),
`PuzzleLibraryImporter`,
`RemotePuzzleFetcher`/`ChunkSequenceStore`/`LibraryProvisioner` for chunked
delivery, and the UserDefaults-backed stores as injectable instances (`UserRatingStore`
— the Rating starts at 1000, `DifficultyModeStore`, `PieceAnimationStore`,
`UserDefaultsBatchStateStore`,
`LibraryStateStore`). Nothing above this module imports SwiftData; SwiftData
models never leak out of it.

### Features (app target)

Views receive `AppDependencies` from the environment; they never construct
stores or read global statics. `TacticsTrainingStore` keeps a plain-dataset
test initializer and coordinates the training flow, while `TacticsSessionStore`
owns current-puzzle interaction state, `TacticsRoundStore` owns batch selection
and navigation, and `TacticsProgressStore` owns rating, outcomes, and persisted
progress. `TacticsScreenViewModel` composes
view-specific presentation ViewModels over the training flow; `RootView`
builds it once per session and injects it via `.environment`, so the store
survives navigation between `HomeView` (the root) and the pushed
`TacticsView`. `RoundTracker` owns an injectable clock and schedules one expiry
wake-up — no polling timers anywhere.

### TCA coexistence (app target only)

Features migrate to TCA one at a time (`Features/Settings` is done; the rest
are still `@Observable` stores). During the mix:

- A feature is either fully TCA (`<Feature>Feature.swift` reducer + a view
  taking `StoreOf<<Feature>Feature>`) or fully `@Observable`; never both in
  one screen. Settings is the reference implementation
  (`SettingsFeature.swift`, `SettingsClients.swift`).
- TCA stores are constructed only at presentation boundaries via the feature's
  static factory (e.g. `Store.settings(dependencies:)`), which wraps
  `Store` creation in `withDependencies` closing over
  `@Environment(AppDependencies.self)`. `AppDependencies` stays the single
  composition root — no liveValue registration, no global/static stores.
- `import ComposableArchitecture`/`Dependencies` may appear only under
  `ios/DailyTactics/Sources/**` and `ios/DailyTactics/Tests/**` (enforced by
  the target dependency graph).
- Reducers never sleep (`Task.sleep`): delays ride injected
  clocks/clients. Every migrated feature ships with its TestStore suite.
- Domain types crossing the boundary stay PuzzleKit `Sendable` value types.

## Interaction rules

- The machine's opening move is automatically played after a short transition.
- Piece travel animates through one derived value: `TacticsTrainingStore.animatedArrival`
  maps each square that just gained a piece to the square it arrived from; an
  empty map means no move is attached (a puzzle load) and nothing slides. The
  board takes a `BoardAnimation` value (arrival map, debug toggles, load
  generation baked into piece ids so loads present fresh views). Keep this
  shape — priority lists of animation signals have repeatedly regressed.
- A wrong legal move is displayed briefly, recorded, and retryable.
- A free analysis board opens from the control row (leading button), seeded
  with the puzzle's raw FEN and oriented like the training
  board at launch; the machine's opening move plays itself half a second
  after load — and again after rewinding to the raw seed or a reset (a user
  move during the pause wins). Settings → Tools → Free board opens the same
  board from the standard opening, with no machine opener, so one person can
  play both sides through a complete game. It has its own clean-room rules
  engine and board view under `Features/Analysis/` (no
  ChessCore/PuzzleKit/TacticsData imports, no training-state access);
  undo/reset and a promotion picker included (no manual flip — boards orient
  automatically), and it never touches rating, progress, or history. Every board screen crowns its
  board with the shared `BoardHeaderView` band (king tile, title over
  subtitle, screen-supplied trailing accessory); on the analysis board it
  shows the held side's king — matching the "you hold white/black" line,
  constant while the side to move alternates (an unseeded free board falls
  back to the side to move) — over
  the live status (the held side is opposite the machine's opener, hidden
  on an unseeded free board), and the material-advantage badge (leading
  side only; hidden while material is even); a SAN move strip with
  per-move piece icons sits above it,
  one horizontally scrolling row with one number per fullmove pair
  (continuing the seed FEN's clock).
- A puzzle can be favorited once finished (play or review): the heart
  outline right of the free-board button toggles `PuzzleProgress.isFavorite`;
- During an active puzzle, Hint is two-stage: the first tap highlights the
  expected move (scored immediately as a loss); a second tap plays the move
  for the player, including the puzzle line's promotion piece. The control
  disables once the puzzle is complete.
- A pawn reaching the last rank opens a promotion picker
  (queen/rook/bishop/knight); the move is submitted only after a choice.
- Home (`Features/Home`) is the root screen: a round card (progress/review
  status, outcome row, rating) carrying `Continue training` / `Review this
  round` and `Next round`, plus history, favorites, and settings entries.
  A new round unlocks after the round window (12 hours; 5 minutes in Debug
  builds); the Home `Next round` button stays tappable-but-disabled inside
  the window while the card shows the unlock time, and a foreground refresh
  lights it regardless of board state. A cold launch lands on Home and never
  starts a round by itself: an incomplete persisted round resumes in Play at
  its saved cursor, a completed one resumes in Review looping from the first
  puzzle, and a fresh round only begins when the user taps `Next round`
  (the fresh-install auto-begin of round one remains the sanctioned
  exception); the view model enforces the same guard. `TacticsView` only
  carries the active batch — its toolbar How-to-play and Settings entries
  stay.
- Settings keeps manual next-chunk download tappable. At 3000 or more untried
  puzzles it explains the threshold; below 3000 it downloads and shows a local,
  semi-transparent spinner instead of a full-screen loading state.
- Round history (`RoundHistory`) is written exactly once per round: neither a
  hint on the final puzzle, re-solving the round in review, nor replaying a
  completed round after a relaunch may skip or duplicate the row (the
  round-end rating snapshot follows the same once-per-round rule).
- Review navigation is round-scoped. After the final puzzle, `Next puzzle` loops
  to the first puzzle and transitions Play mode into Review mode.
- Review mode keeps Hint, move interaction, and progress updates,
  but must never change the user's Rating.
- Review must not mutate the live solve result or trigger an automatic reply.
- User-facing strings (including board accessibility labels) go through the
  en/zh-Hans string tables; add both languages together.
- The layout should fit iPhone SE and larger devices without scrolling in the
  normal Dynamic Type size.

## Coding standards

- Prefer small value types and descriptive names.
- Keep view state on `@MainActor`.
- Avoid global mutable state and arbitrary sleeps for correctness.
- Keep animation timing outside domain rules.
- Preserve accessibility labels for board squares and controls.
- Keep third-party notices up to date when assets change.

## Verification

After changes:

```sh
cd ios
mise x tuist@4.197.3 -- tuist install   # after editing Tuist/Package.swift or on a fresh clone
mise x tuist@4.197.3 -- tuist generate
xcrun xcodebuild test -workspace DailyTactics.xcworkspace -scheme DailyTactics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Build against the **workspace**, not the `-project`: the external Swift
packages (TCA) are workspace members, and a `-project` build fails with
missing resource-bundle errors. If the simulator name alone doesn't match
(e.g. when the newest runtime outranks the device's), append `,OS=<version>`
to the destination.

(`tuist test` resolves only workspace-level schemes, which this project no
longer generates — run xcodebuild instead.)

For UI/layout changes, also compile an iPhone SE simulator destination. Do not
hand-edit generated `.xcodeproj` files.
