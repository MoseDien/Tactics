# AGENTS.md

## Project Overview

This repository contains an iOS application for practicing chess tactics.

The app focuses on short, repeatable tactical exercises rather than full-game
play. Users are shown a chess position, make moves on an interactive board,
receive immediate feedback, and can step through the solution line to study it.

The current build is:

- iOS-only
- Built with Swift and SwiftUI
- Fully usable offline
- Managed with Tuist (single target)
- Backed by a bundled JSON puzzle set derived from Lichess data
- Focused on tactical training and completion tracking

Do not add unnecessary backend, account, social, AI, or multiplayer features
unless explicitly requested.

---

## Current State

The tactical training loop is implemented and exercised by unit tests:

- A bundled dataset of **1,000 puzzles** (`DailyTactics/Resources/puzzles.json`),
  generated from a local Lichess SQLite export.
- Each run deals a **random batch of three** puzzles from the dataset.
- Tap-to-move interaction with **basic chess-rule validation**; wrong legal
  moves snap back, illegal moves are ignored.
- **Special moves** in solution lines — castling, en passant, promotion
  (auto-queen) — are applied correctly.
- Automatic opponent reply, puzzle completion, and a `<` / `>` **review
  scrubber** to think through a line ply by ply.
- Board **auto-orients** to the player's color on each load, plus a manual flip.
- **SwiftData** records completed puzzles (`PuzzleProgress`), powering a
  "Solved" counter.

Deferred on purpose (see Roadmap): full check/pin legality, castling-through-
check, underpromotion picker, spaced-repetition review scheduling, statistics,
theme filtering, and accounts/cloud.

---

## Product Goal

The core user loop is:

```text
Open the app
  → a random batch of puzzles is dealt
  → see a tactical position (board oriented to your color)
  → make a move on the board
  → correct: continue the line; wrong: the piece snaps back
  → finish the line → puzzle marked solved
  → next puzzle (or step through the line with < / > to study)
```

The product should help users recognize recurring tactical patterns, not merely
memorize moves.

---

## Technology Stack

- Swift (strict concurrency where practical) and SwiftUI
- `@Observable` view models on the main actor
- SwiftData for completion state (`PuzzleProgress`)
- Tuist for project generation
- XCTest for domain tests
- A bundled JSON dataset for puzzle content

Prefer Apple platform APIs over third-party libraries. Chess rules, puzzle
behavior, and persistence are kept behind internal types so implementations can
be replaced later.

---

## Project Layout

A single Tuist target with source organized by concern:

```text
.
├── Project.swift              # Tuist manifest (app + test targets)
├── Tuist.swift
├── CLAUDE.md
├── README.md
├── THIRD_PARTY_NOTICES.md
├── lichess/                   # gitignored: raw data + import/export scripts (local only)
└── DailyTactics/
    ├── Sources/
    │   ├── ChessCore/         # Chess.swift
    │   ├── PuzzleKit/         # Puzzle.swift
    │   ├── Persistence/       # PuzzleProgress.swift
    │   ├── Features/Tactics/  # TacticsView, ChessBoardView, TacticsViewModel
    │   └── DailyTacticsApp.swift
    ├── Resources/             # puzzles.json, piece art, license
    └── Tests/                 # ChessAndPuzzleTests.swift
```

The exact layout may evolve, but the boundaries between chess rules, puzzle
behavior, persistence, and UI must remain clear.

### Dependency Direction

Logical layering (within the single target):

```text
DailyTacticsApp → Features/Tactics → PuzzleKit → ChessCore
                                   ↘ Persistence
```

- `ChessCore` must not depend on SwiftUI, SwiftData, or app-specific code.
- `PuzzleKit` depends on `ChessCore` only — no SwiftUI/SwiftData.
- `Persistence` is SwiftData; it is injected into features, not imported by
  `ChessCore`/`PuzzleKit`.
- Low-level modules must not import feature modules.

---

## Tuist

Tuist is the source of truth for the Xcode project. Do not hand-maintain the
`.xcodeproj` as the primary definition.

```bash
tuist install     # if/when dependencies are added
tuist generate    # regenerate the workspace
tuist test        # build + run tests
```

`Project.swift` defines two targets — the `DailyTactics` app and the
`DailyTacticsTests` unit-test target. Sources and resources are globbed:

```swift
sources: ["DailyTactics/Sources/**"],
resources: ["DailyTactics/Resources/**"]
```

So new files under those globs are picked up by `tuist generate` with no manifest
edit. Do not introduce additional targets without a clear architectural reason.

---

## Architecture

Keep chess rules and puzzle behavior independent from UI.

### ChessCore (`Chess.swift`)

Chess-domain behavior — pure value types, `Sendable`, no UI/storage imports:

- `PieceColor`, `PieceKind`, `Piece`, `Square`, `ChessMove`
- `Board`: FEN parsing (board + side to move), `apply(_:)`, `isLegal(_:for:)`
- UCI move conversion and round-tripping

`Board.apply` handles castling (relocates the rook), en passant (removes the
captured pawn), and promotion (via `ChessMove.promotion`).

`Board.isLegal` validates **basic** piece movement: shape, path blocking, and
self-capture. It does **not** model check/pin legality, castling rights, or en
passant availability — those are deferred. Because puzzle solution moves come
from a trusted line, the view model accepts the expected move unconditionally
and only uses `isLegal` to gate exploratory (non-solution) moves.

### PuzzleKit (`Puzzle.swift`)

Puzzle-specific behavior:

- `PuzzleTheme` (stable identifiers, not display strings)
- `Puzzle` (`Identifiable`, `Codable`) — core fields plus the full Lichess
  metadata (`ratingDeviation`, `popularity`, `playCount`, `gameUrl`,
  `openingTags`, all optional for future use) + `Puzzle.samples` (test fixtures)
  and `Puzzle.loadBundled()` (decodes `puzzles.json`, falls back to `samples`
  only if the file is absent; malformed data is a fatal error)
- `PuzzleSessionState` state machine
- `PuzzleSession`: the line-walking engine (apply expected/opponent moves,
  correctness check, review stepping via `replay`, restart)

### Persistence (`PuzzleProgress.swift`)

- `PuzzleProgress` (`@Model`): `{ puzzleId, isCompleted, completedAt }` — the
  per-user "done" state, separate from static puzzle content.
- `PuzzleProgressStore`: a `@MainActor` façade over `ModelContext` for marking
  and querying completion. Injected into the view model; do not let SwiftData
  types leak into `ChessCore`/`PuzzleKit`.

### Features/Tactics

- `ChessBoardView`: renders the 8×8 board, pieces, move/selection highlights,
  and coordinate labels; supports a flipped perspective (data-driven).
- `TacticsViewModel` (`@MainActor @Observable`): owns the dataset, the current
  3-puzzle batch, the active `PuzzleSession`, board flip, and the SwiftData
  store; translates taps into moves and drives feedback.
- `TacticsView`: header (progress + solved count), board, control bar
  (`<` count `>` | flip), and state-driven feedback.

---

## Puzzle Session State

```swift
enum PuzzleSessionState: Equatable, Sendable {
    case waitingForMove
    case opponentMoving
    case incorrectMove
    case solved
}
```

Flow:

```text
init → opponentMoving            (the opponent's opening move auto-plays)
  → waitingForMove
      user move
        ├── correct + line continues → opponentMoving → waitingForMove
        ├── correct + line complete  → solved
        └── incorrect                → incorrectMove → waitingForMove
```

The opponent move is applied automatically after a short UI transition. Business
logic never depends on animation timing — a separate `isReviewing` flag marks
positions reached via the manual `<`/`>` scrubber, so the auto-reply is
suppressed and the view shows a static "Opponent's reply" instead of a spinner.

---

## Data Source

Lichess puzzle data is the source dataset. The entire `lichess/` directory (raw
database and the import/export scripts) is local and **not** committed, and the
raw database is never loaded by the app.

Pipeline:

```text
Lichess puzzle CSV/Zstandard archive
  → import_lichess_puzzles.py → local SQLite (lichess/data/, gitignored)
  → export_puzzles.py         → DailyTactics/Resources/puzzles.json (bundled)
```

`export_puzzles.py` writes the **full** Lichess metadata
(`id, fen, moves, rating, ratingDeviation, popularity, playCount, themes,
gameUrl, openingTags`) so it is available for future features; theme tags are
filtered down to the `PuzzleTheme` enum. Always preserve Lichess attribution
and license information (`THIRD_PARTY_NOTICES.md`).

---

## Tactical Themes

Theme names in the domain layer are stable identifiers (Lichess tags kept
verbatim where they match):

```swift
enum PuzzleTheme: String, Codable, CaseIterable, Sendable {
    case fork, pin, skewer, discoveredAttack, sacrifice, mate
    case defensiveMove, endgame, advantage, middlegame, rookEndgame, short
}
```

Localization belongs in the presentation layer.

---

## Roadmap

Items intentionally deferred until the core loop is stable:

- Full legality: check/pin detection, castling-through-check, castling rights.
- Promotion piece picker (currently auto-queen).
- Spaced-repetition review scheduling (simple rules first, behind a protocol).
- Statistics: streaks, accuracy, rating, daily activity.
- Theme filtering and "similar puzzle" discovery.
- SwiftData-backed attempt history and review queue.

Review scheduling, when added, should be isolated behind:

```swift
protocol PuzzleReviewScheduling: Sendable {
    func nextReviewDate(
        after result: PuzzleResult,
        successfulReviewCount: Int,
        now: Date
    ) -> Date
}
```

---

## Coding Standards

### Swift

- Use Swift's strict concurrency model where practical.
- Prefer value types for domain models; mark them `Sendable`.
- Avoid force unwraps and global mutable state.
- Use descriptive names, small focused functions, dependency injection.
- Keep UI state on the main actor.
- Do not use arbitrary delays to fix state bugs (delays are only for UI
  transitions and must not be load-bearing for correctness).
- Fail clearly on malformed bundled data; prefer typed errors. Development
  builds may `preconditionFailure`/`fatalError` for impossible internal states.

### SwiftUI

- Keep views declarative; move non-trivial logic into the view model/session.
- Avoid very large view bodies; give stable identity to squares and pieces.
- Keep animation separate from domain mutation.
- Keep the board usable across iPhone sizes and in light/dark appearance.

---

## Testing Strategy

Prioritize domain tests over UI/snapshot tests. The session and board are fully
testable without launching SwiftUI. Current coverage includes:

- FEN parsing and side to move
- Square / UCI round-trip and promotion parsing
- Expected-move recognition; incorrect moves leave the board unchanged
- Full line → `solved`; restart restores the puzzle
- Review stepping (forward/back, bounds, `isReviewing`)
- Legality: piece shapes, path blocking, pawn push/capture, castling, en passant
- Puzzle JSON decoding; SwiftData completion store (idempotent, in-memory)
- Bundled samples are playable to `solved` with unique IDs

A feature is not complete merely because the UI appears correct.

---

## Commands

Kept current in the README. Typical:

```bash
mise x tuist@4.197.3 -- tuist generate
mise x tuist@4.197.3 -- tuist test
```

A clean build is also possible with `xcodebuild` against the generated
workspace. Do not commit user-specific Xcode state
(`xcuserdata/`, `Derived/`, `*.xcworkspace`, `*.xcodeproj`).

---

## Out of Scope Until Requested

Online play, matchmaking, chat, friends, leaderboards, social feeds,
user-generated puzzles, full-game Stockfish analysis, AI coaching, server-side
accounts, cross-device sync, subscriptions, advertising, complex gamification,
Android, and web.

---

## Agent Behavior

When making changes:

1. Read this file first.
2. Inspect existing architecture before adding new abstractions.
3. Preserve Tuist as the project source of truth.
4. Keep changes limited to the requested task; do not expand product scope.
5. Add or update tests for domain behavior.
6. Run `tuist generate` and `tuist test`; report what changed, what was
   verified, and any remaining limitation.
7. When requirements are ambiguous, prefer the smallest implementation that
   advances the core tactical-training loop.
