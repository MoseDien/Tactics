# DailyTactics

An iOS-only, offline SwiftUI app for solving focused chess tactics. Each run
deals a small batch of random puzzles from a bundled Lichess dataset; solve
them by playing the correct line on an interactive board.

Chess piece artwork uses the Lichess `chessnut` SVG set by Alexis Luengas,
licensed under Apache License 2.0 — see `THIRD_PARTY_NOTICES.md`.

## Features

- **1,000 bundled puzzles** (`Resources/puzzles.json`) sampled from the Lichess
  database; each run deals three at random.
- **Tap-to-move** with basic chess-rules validation (piece movement, path
  blocking, self-capture). A wrong *legal* move briefly shows on the target then
  snaps back to its origin; an *illegal* move is ignored.
- **Special moves** in the solution lines — castling, en passant, and promotion
  (auto-queen) — are applied correctly.
- **Automatic opponent reply**, puzzle completion, and a step-by-step review
  scrubber (`<` / `>`) to think through the line move by move.
- **Board orientation** flips to the player's perspective on every load, with a
  manual flip toggle.
- **Completion tracking** via SwiftData (`PuzzleProgress`), backing the "Solved"
  counter.

## Puzzle dataset

The bundled set is generated from a local Lichess SQLite export. The entire
`lichess/` directory (raw database **and** the import/export scripts) is local
and **not** committed — see `.gitignore`. If you have that local setup,
regenerate the bundled file with:

```sh
python3 lichess/tools/export_puzzles.py \
    lichess/data/lichess_puzzles.sqlite \
    DailyTactics/Resources/puzzles.json \
    --count 1000
```

Lichess theme tags are filtered down to the app's `PuzzleTheme` enum.

## Requirements

- Xcode 16 or newer
- Tuist 4.x
- iOS 17 or newer

## Build & run

```sh
mise x tuist@4.197.3 -- tuist generate
open DailyTactics.xcworkspace
```

Run the domain tests:

```sh
mise x tuist@4.197.3 -- tuist test
```

CI-friendly build:

```sh
xcodebuild \
  -workspace DailyTactics.xcworkspace \
  -scheme DailyTactics \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Architecture

A single Tuist target (`DailyTactics`) with source organized by concern. Chess
rules and puzzle logic have **no** SwiftUI or SwiftData dependencies.

```
Sources/
  ChessCore/            Board, pieces, FEN, UCI moves, basic legality
  PuzzleKit/            Puzzle model, session state machine, bundled loader
  Persistence/          SwiftData PuzzleProgress + store (completion tracking)
  Features/Tactics/     TacticsView, ChessBoardView, TacticsViewModel
  DailyTacticsApp.swift App entry point + SwiftData container
Resources/              puzzles.json, piece artwork, license
Tests/                  domain unit tests (XCTest)
```
