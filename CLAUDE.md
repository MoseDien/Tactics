# DailyTactics contributor guide

## Mission

当前阶段只开发和维护 iOS 版本。Android 工程暂时冻结，待 iOS 完成后再恢复 Android 开发。

Maintain a small, offline iOS chess-tactics trainer. Prioritize a fast loop:
load a puzzle, play the correct line, receive feedback, review the line, and
move to the next puzzle.

Do not add backend services, accounts, social features, AI, multiplayer,
subscriptions, analytics, or cloud sync unless explicitly requested.

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

```text
DailyTacticsApp
  ├── Features/Tactics
  │     ├── PuzzleKit
  │     ├── ChessCore
  │     └── Persistence (injected)
  ├── Features/Settings     difficulty, how-to-play, history entry
  └── Features/Onboarding   first-launch library import
```

### ChessCore

Pure, `Sendable` chess value types: pieces, colors, squares, UCI moves, FEN
parsing (placement, side to move, castling rights, en-passant target), board
application, and full legality validation (shape, check, pins, castling, en
passant, promotion). It must not import SwiftUI, SwiftData, or feature code.

### PuzzleKit

Puzzle decoding and the `PuzzleSession` state machine. Lichess move arrays
start with the machine setup move (`moves[0]`); the player starts at
`moves[1]`, then turns alternate. Review replay is deterministic and must not
depend on animation timing.

### Persistence

SwiftData models: `PuzzleRecord` (imported library), `PuzzleProgress`
(per-puzzle attempt/completion/failure), `RoundHistory` (one row per completed
batch), `RatingSnapshot` (one row per completed batch, the settled rating —
shown as a trend chart in Settings). Supporting stores: `PuzzleLibrary`
(`PuzzleLibraryImporter`,
`LibraryStateStore`) for the first-launch import gate, `BatchStore` /
`BatchConfiguration` for the 8-hour batch window (5 minutes in Debug builds),
`DifficultyMode` for the
Easy/Medium/Hard setting, and `Rating.swift` (`PuzzleRatingCalculator`,
`UserRatingStore`) for the local Elo-like policy — the current Rating starts
at 1500 and persists through `UserDefaults`. Persistence models must not
leak into ChessCore or PuzzleKit.

### Features/Tactics

`TacticsView` composes the compact, Lichess-inspired training layout.
`ChessBoardView` is responsible only for board rendering and interaction
events. `TacticsViewModel` coordinates the session, Hint, promotion picker,
review controls, orientation, Rating, and persistence. `ReviewRoundView`
hosts the per-puzzle review sheet and the Settings→History round browser.

## Interaction rules

- The machine's opening move is automatically played after a short transition.
- A wrong legal move is displayed briefly, recorded, and retryable.
- A Hint highlights the expected move but does not play it.
- A pawn reaching the last rank opens a promotion picker
  (queen/rook/bishop/knight); the move is submitted only after a choice.
- A new batch unlocks 4 hours after the current batch started; tapping
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
