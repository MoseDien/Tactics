# DailyTactics contributor guide

## Mission

当前阶段只开发和维护 iOS 版本。Android 工程暂时冻结，待 iOS 完成后再恢复 Android 开发。

Maintain a small, offline iOS chess-tactics trainer. Prioritize a fast loop:
load a puzzle, play the correct line, receive feedback, review the line, and
move to the next puzzle.

Do not add backend services, accounts, social features, AI, multiplayer,
subscriptions, analytics, or cloud sync unless explicitly requested.
(The one sanctioned network behavior is chunked puzzle downloads: when the
untried pool can't fill a batch, the next `puzzle-NNNN.json` is fetched from
the deployed catalog and imported; failures fall back silently.)

## Technology

- Swift 6, SwiftUI, Swift Concurrency
- iOS 17+
- Tuist 4.x is the source of truth for the Xcode project under `ios/`
- SwiftData only behind `Persistence` interfaces
- XCTest for domain and feature behavior

Bundle ID: `com.dienbell.tactics`.

The current Daily Tactics, batch, persistence, difficulty, promotion, and
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
  ├── BatchTracker / TacticsPacing (observable batch window, injectable clock & pacing)
  ├── Features/Tactics
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
`BatchPolicy`/`BatchWindow`/`BatchLookup`, `RoundSelector` with injectable
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
— the Rating starts at 1500, `DifficultyModeStore`, `PieceAnimationStore`,
`UserDefaultsBatchStateStore`,
`LibraryStateStore`). Nothing above this module imports SwiftData; SwiftData
models never leak out of it.

### Features (app target)

Views receive `AppDependencies` from the environment; they never construct
stores or read global statics. `TacticsViewModel` keeps a plain-dataset test
initializer. `BatchTracker` owns an injectable clock and schedules one expiry
wake-up — no polling timers anywhere.

## Interaction rules

- The machine's opening move is automatically played after a short transition.
- Piece travel animates through one derived value: `TacticsViewModel.animatedArrival`
  maps each square that just gained a piece to the square it arrived from; an
  empty map means no move is attached (a puzzle load) and nothing slides. The
  board takes a `BoardAnimation` value (arrival map, debug toggles, load
  generation baked into piece ids so loads present fresh views). Keep this
  shape — priority lists of animation signals have repeatedly regressed.
- A wrong legal move is displayed briefly, recorded, and retryable.
- A Hint highlights the expected move but does not play it.
- A pawn reaching the last rank opens a promotion picker
  (queen/rook/bishop/knight); the move is submitted only after a choice.
- A new batch unlocks after the batch window (8 hours; 5 minutes in Debug builds); tapping
  `Next batch` inside the window shows a wait message and stays in Review.
- Round history (`RoundHistory`) is written exactly once per batch: neither a
  hint on the final puzzle nor re-solving the batch in review may skip or
  duplicate the row.
- Review navigation is batch-scoped. After the final puzzle, `Next puzzle` loops
  to the first puzzle and transitions Play mode into Review mode.
- Review mode keeps Hint, board flipping, move interaction, and progress updates,
  but must never change the user's Rating.
- Review must not mutate the live solve result or trigger an automatic reply.
- User-facing strings (including board accessibility labels) go through the
  en/zh-Hans string tables; add both languages together.
- The layout should fit iPhone SE and larger devices without scrolling in the
  normal Dynamic Type size. `ScrollView` remains as an accessibility fallback.

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
mise x tuist@4.197.3 -- tuist generate
xcrun xcodebuild test -project DailyTactics.xcodeproj -scheme DailyTactics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

(`tuist test` resolves only workspace-level schemes, which this project no
longer generates — run xcodebuild against the generated project instead.)

For UI/layout changes, also compile an iPhone SE simulator destination. Do not
hand-edit generated `.xcodeproj` files.
