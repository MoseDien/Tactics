# DailyTactics

The repository root contains [`index.html`](index.html), a static English
landing page for iTactics. It can be published directly with GitHub Pages for
App Store review and product information.

DailyTactics is an offline iOS SwiftUI app for short chess-tactics sessions.
It bundles a compact Lichess-derived puzzle set, lets the player solve one
line at a time, and stores progress locally.

## Current product

当前开发优先级为 iOS。Android 工程暂时保留在 `android/`，但暂停功能开发；待 iOS 版本完成并稳定后再继续 Android。

- iOS-only, iOS 17+, Swift 6, SwiftUI, Tuist 4.x
- Bundle identifier: `com.dienbell.tactics`, display name **iTactics**
- On first launch the entire bundled library (10 rating tiers, ~10,000 puzzles)
  is imported into SwiftData in one pass behind a loading screen; a decode
  failure shows an error with Retry instead of silently degrading
- Daily puzzle batches are selected from SwiftData and can be reviewed after completion
- After a batch is complete, `Next puzzle` remains available and enters Review mode,
  looping through the current batch without changing Rating
- Each batch draws 5 random not-yet-attempted puzzles (queried only at batch
  start); a new batch unlocks every 8 hours (5 minutes in Debug builds), and
  the difficulty setting
  (Easy/Medium/Hard) filters new batches relative to the user's Rating
- Lichess `chessnut` SVG pieces are bundled locally under Apache 2.0
- The first move in every Lichess line is the machine's setup move; user and
  machine then alternate through the remaining UCI moves
- Tap-to-move interaction with full legality validation (check, pins,
  castling, en passant)
- Pawn promotions open a 4-way piece picker (queen/rook/bishop/knight);
  under-promotion puzzles are solvable
- Wrong legal moves are shown briefly and recorded; the player can retry
- Piece movement animates: moves slide (0.18s ease-out, including the
  castling rook), a freshly loaded board fades in, wrong-move previews
  slide out and back; board flips render instantly. Debug builds expose
  two toggles to disable either animation
- Hint button highlights the expected move without auto-playing it
- Review mode keeps Hint, board flipping, move interaction, and progress available;
  it never changes the user's Rating
- Board orientation follows the player's color and can be flipped manually
- A local Elo-like puzzle Rating starts at 1500 and is persisted with
  `UserDefaults`; one snapshot per completed batch feeds a Rating trend
  chart in Settings
- SwiftData stores completion/failure history plus per-batch round history
  (browsable in Settings → History with per-puzzle review)
- A storyboard launch screen shows the wordmark — a red "i" before
  "Tactics" (the app's logo) on white, centered
- Localized in English and Simplified Chinese

The app intentionally does not include accounts, networking, Stockfish,
analytics, subscriptions, or cloud synchronization.

## Rating

The current Rating is a local training score, not an official Lichess rating.
The calculator uses the standard expected-score formula with `K = 32`:

```text
expected = 1 / (1 + 10 ^ ((puzzleRating - userRating) / 400))
change   = round(32 * (result - expected))
```

`result` is `1` for a clean solve. A **first-attempt mistake** does not change
the Rating at all (the puzzle is only marked attempted); using a **Hint**
settles the puzzle immediately as a loss and deducts points. A round that
would round to 0 is forced to +1 (solve) or −1 (loss), so every settled puzzle
moves the score. Scores are clamped to `400...3000`. The value is deliberately
isolated in `PuzzleKit/RatingPolicy.swift` so the policy can be replaced later.

## Project layout

```text
ios/
  Project.swift            one manifest: 4 product targets + 4 test targets
  ChessCore/               pure chess value types and full legality
  PuzzleKit/               domain: puzzles, session, policies, repository ports
  TacticsData/             SwiftData models, repositories, bundled tiers, defaults stores
  DailyTactics/
    Sources/
      AppDependencies.swift    composition root (injected via environment)
      BatchTracker.swift       observable batch window, injectable clock
      TacticsPacing.swift      injectable interaction timing
      Features/Tactics/        training view, board, view model, round history UI
      Features/Settings/       difficulty, rating trend chart, history entry
      Features/Onboarding/     first-launch library import screen
      DailyTacticsApp.swift    app entry point
    Resources/                 assets, localization, legal
    Tests/                     view-model + batch-tracker tests, fakes
android/                    Android client (frozen)
data/source/                local SQLite source data (ignored by Git)
tools/                      puzzle import/export scripts
third_party/                Lichess reference images (not bundled)
```

Dependency direction is enforced by the target graph:
`DailyTactics → {PuzzleKit, TacticsData}`, `TacticsData → PuzzleKit`,
`PuzzleKit → ChessCore`. Only TacticsData imports SwiftData; the app target
imports none of it. Domain code does not import SwiftUI.

## Requirements and commands

```sh
cd ios
# Generate the Xcode project
mise x tuist@4.197.3 -- tuist generate

# Open the generated project
open DailyTactics.xcodeproj

# Run all tests (tuist test resolves only workspace schemes, which this
# project no longer generates)
xcrun xcodebuild test -project DailyTactics.xcodeproj -scheme DailyTactics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

CI-style build:

```sh
xcodebuild \
  -project DailyTactics.xcodeproj \
  -scheme DailyTactics \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Puzzle data

`ios/TacticsData/Resources/Puzzles/puzzle-0000.json` is the app-bundled chunk
(1000 puzzles, read through `BundledPuzzleSource`). Further chunks arrive over
the network: when the untried pool can't fill a batch, the app fetches the
next `puzzle-NNNN.json` from the deployed catalog and imports it (offline
failures fall back to replaying attempted puzzles). Chunks are generated from
the raw Lichess SQLite database by `tools/export_puzzle_chunk.py`, which also
marks exported ids in the DB so no puzzle ships twice:

```sh
# next chunk (auto-advances past the highest recorded sequence)
python tools/export_puzzle_chunk.py data/source/lichess_puzzles.sqlite puzzles
# the app-bundled chunk
python tools/export_puzzle_chunk.py data/source/lichess_puzzles.sqlite puzzles --sequence 0
```

The raw database lives under `data/source/` (ignored by Git); only the generated
JSONs are part of the mobile bundle. Third-party artwork and licensing details
are in `THIRD_PARTY_NOTICES.md`.

The older scripts under `tools/` (`export_tier_puzzles.py`,
`export_puzzles.py`, `import_lichess_puzzles.py`) produced the retired
tier-file layout and are kept for reference.
