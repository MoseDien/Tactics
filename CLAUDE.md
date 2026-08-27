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

The current Rating Assessment, Daily Tactics, round, persistence, and level
transition rules are documented in [docs/BUSINESS_LOGIC.md](docs/BUSINESS_LOGIC.md).

## Architecture

```text
DailyTacticsApp
  └── Features/Tactics
        ├── PuzzleKit
        ├── ChessCore
        └── Persistence (injected)
```

### ChessCore

Pure, `Sendable` chess value types: pieces, colors, squares, UCI moves, FEN
parsing, board application, and basic movement validation. It must not import
SwiftUI, SwiftData, or feature code.

### PuzzleKit

Puzzle decoding and the `PuzzleSession` state machine. Lichess move arrays
start with the machine setup move (`moves[0]`); the player starts at
`moves[1]`, then turns alternate. Review replay is deterministic and must not
depend on animation timing.

### Persistence

`PuzzleProgress` stores completion/failure history in SwiftData. `Rating.swift`
contains the local Rating policy and `UserRatingStore`; the current Rating
starts at 1500 and persists through `UserDefaults`. Persistence models must not
leak into ChessCore or PuzzleKit.

### Features/Tactics

`TacticsView` composes the compact, Lichess-inspired training layout.
`ChessBoardView` is responsible only for board rendering and interaction
events. `TacticsViewModel` coordinates the session, Hint, review controls,
orientation, Rating, and persistence.

## Interaction rules

- The machine's opening move is automatically played after a short transition.
- A wrong legal move is displayed briefly, recorded, and retryable.
- A Hint highlights the expected move but does not play it.
- `<` and `>` are review controls, not undo controls. They are disabled during
  active solving and become available after solving or entering review.
- Review must not mutate the live solve result or trigger an automatic reply.
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
mise x tuist@4.197.3 -- tuist test
```

For UI/layout changes, also compile an iPhone SE simulator destination. Do not
hand-edit generated `.xcodeproj` files.
