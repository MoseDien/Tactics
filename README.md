# DailyTactics

DailyTactics is an offline iOS SwiftUI app for short chess-tactics sessions.
It bundles a compact Lichess-derived puzzle set, lets the player solve one
line at a time, and stores progress locally.

## Current product

- iOS-only, iOS 17+, Swift 6, SwiftUI, Tuist 4.x
- Bundle identifier: `com.dienbell.tactics`
- Three random puzzles are selected for each session
- Lichess `chessnut` SVG pieces are bundled locally under Apache 2.0
- The first move in every Lichess line is the machine's setup move; user and
  machine then alternate through the remaining UCI moves
- Tap-to-move interaction with basic movement validation
- Castling, en passant, and automatic queen promotion in trusted puzzle lines
- Wrong legal moves are shown briefly and recorded; the player can retry
- Hint button highlights the expected move without auto-playing it
- `<` / `>` review controls are locked during active play and become available
  after the puzzle is solved or review has started
- Board orientation follows the player's color and can be flipped manually
- A local Elo-like puzzle Rating starts at 1500 and is persisted with
  `UserDefaults`
- SwiftData stores completion and failure history for future review features

The app intentionally does not include accounts, networking, Stockfish,
analytics, subscriptions, or cloud synchronization.

## Rating

The current Rating is a local training score, not an official Lichess rating.
The calculator uses the standard expected-score formula with `K = 32`:

```text
expected = 1 / (1 + 10 ^ ((puzzleRating - userRating) / 400))
change   = round(32 * (result - expected))
```

`result` is `1` for a clean solve and `0` after a mistake or hint. Scores are
clamped to `400...3000`. The value is deliberately isolated in
`Persistence/Rating.swift` so the policy can be replaced later.

## Project layout

```text
Project.swift
Tuist.swift
DailyTactics/
  Sources/
    ChessCore/              board, FEN, UCI, basic move legality
    PuzzleKit/              puzzle model and line/session state machine
    Persistence/            SwiftData progress and local Rating
    Features/Tactics/       training view, board, and view model
    DailyTacticsApp.swift   app entry point and model container
  Resources/                puzzles.json, SVG pieces, license
  Tests/                    domain and feature behavior tests
lichess/                    local-only dataset/tools (ignored by Git)
```

The dependency direction is `Features → PuzzleKit → ChessCore`; persistence is
injected at the feature boundary. Domain code does not import SwiftUI or
SwiftData.

## Requirements and commands

```sh
# Generate the Xcode workspace
mise x tuist@4.197.3 -- tuist generate

# Open the generated workspace
open DailyTactics.xcworkspace

# Run all tests
mise x tuist@4.197.3 -- tuist test
```

CI-style build:

```sh
xcodebuild \
  -workspace DailyTactics.xcworkspace \
  -scheme DailyTactics \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Puzzle data

`DailyTactics/Resources/puzzles.json` is the app's compact bundled dataset.
The raw Lichess export and local import tools live under `lichess/` and are not
part of the mobile bundle. Third-party artwork and licensing details are in
`THIRD_PARTY_NOTICES.md`.
