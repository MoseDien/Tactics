# DailyTactics

DailyTactics is an offline iOS SwiftUI app for short chess-tactics sessions.
It bundles a compact Lichess-derived puzzle set, lets the player solve one
line at a time, and stores progress locally.

## Current product

当前开发优先级为 iOS。Android 工程暂时保留在 `android/`，但暂停功能开发；待 iOS 版本完成并稳定后再继续 Android。

- iOS-only, iOS 17+, Swift 6, SwiftUI, Tuist 4.x
- Bundle identifier: `com.dienbell.tactics`
- On first launch the entire bundled library (10 rating tiers, ~10,000 puzzles)
  is imported into SwiftData in one pass behind a loading screen
- Daily puzzle batches are selected from SwiftData and can be reviewed after completion
- After a batch is complete, `Next puzzle` remains available and enters Review mode,
  looping through the current batch without changing Rating
- Each round draws 5 random not-yet-attempted puzzles from the database
  (queried only at the start of each round); difficulty is mixed across tiers
- Lichess `chessnut` SVG pieces are bundled locally under Apache 2.0
- The first move in every Lichess line is the machine's setup move; user and
  machine then alternate through the remaining UCI moves
- Tap-to-move interaction with basic movement validation
- Castling, en passant, and automatic queen promotion in trusted puzzle lines
- Wrong legal moves are shown briefly and recorded; the player can retry
- Hint button highlights the expected move without auto-playing it
- Review mode keeps Hint, board flipping, move interaction, and progress available;
  it never changes the user's Rating
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
ios/
  Project.swift
  Tuist.swift
  DailyTactics/
  Sources/
    ChessCore/              board, FEN, UCI, basic move legality
    PuzzleKit/              puzzle model and line/session state machine
    Persistence/            SwiftData progress and local Rating
    Features/Tactics/       training view, board, and view model
    DailyTacticsApp.swift   app entry point and model container
  Resources/                SVG pieces, license
  Resources/puzzles/        rating tiers (1000–1900.json) + rating_puzzles.json
  Tests/                    domain and feature behavior tests
android/                    Android client
data/source/                local SQLite source data (ignored by Git)
tools/                      puzzle import/export scripts
third_party/                Lichess reference images and notices
```

The dependency direction is `Features → PuzzleKit → ChessCore`; persistence is
injected at the feature boundary. Domain code does not import SwiftUI or
SwiftData.

## Requirements and commands

```sh
cd ios
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

`ios/DailyTactics/Resources/puzzles/` contains the bundled puzzle data: ten
rating-tier files (`1000.json`–`1900.json`, 1000 puzzles each) plus
Puzzle tier JSON files are generated from
the raw Lichess SQLite database by `tools/export_tier_puzzles.py`:

```sh
python tools/export_tier_puzzles.py data/source/lichess_puzzles.sqlite ios/DailyTactics/Resources/puzzles
```

The raw database lives under `data/source/` (ignored by Git); only the generated
JSONs are part of the mobile bundle. Third-party artwork and licensing details
are in `THIRD_PARTY_NOTICES.md`.
