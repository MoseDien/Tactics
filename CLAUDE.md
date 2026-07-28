# AGENTS.md

## Project Overview

This repository contains an iOS mobile application for practicing chess tactics.

The app focuses on short, repeatable tactical exercises rather than full-game play. Users are shown a chess position, make moves on an interactive board, receive immediate feedback, and gradually review previously failed puzzles.

The first release should be:

- iOS-only
- Built with Swift and SwiftUI
- Fully usable offline
- Managed with Tuist
- Backed by local puzzle data
- Focused on tactical training and mistake review
- Small enough to complete and publish as a first App Store version

Do not add unnecessary backend, account, social, AI, or multiplayer features unless explicitly requested.

---

## Product Goal

The core user loop is:

```text
Open the app
  ↓
See a tactical chess position
  ↓
Make a move on the board
  ↓
Receive correct or incorrect feedback
  ↓
Continue the tactical line
  ↓
Finish the puzzle
  ↓
Move to the next puzzle or review the explanation
```

The product should help users recognize recurring tactical patterns, not merely memorize moves.

Long-term, the app may connect:

```text
Puzzle
→ Tactical pattern
→ Recognition clues
→ Similar puzzles
→ Mistake review
```

---

## Core MVP Features

The MVP may eventually include:

1. Tactical puzzle training
2. Interactive chessboard
3. Correct and incorrect move feedback
4. Tactical theme filtering
5. Local learning history
6. Failed-puzzle review
7. Basic progress and streak statistics

However, agents must prioritize the first runnable version described later in this document before implementing the broader MVP.

---

## Technology Stack

Use the following technologies unless a task explicitly requires otherwise:

- Swift
- SwiftUI
- Swift Concurrency
- SwiftData for user progress and local state
- Tuist for project generation and dependency management
- XCTest and Swift Testing where appropriate
- A local JSON, SQLite, or bundled database for puzzle content

Prefer Apple platform APIs over third-party libraries.

A third-party chess library may be introduced only when it clearly reduces risk and has a compatible license. Keep chess rules, puzzle flow, and persistence behind internal interfaces so implementations can be replaced later.

---

## Tuist Requirements

Tuist is the source of truth for the Xcode project structure.

Do not manually maintain an `.xcodeproj` as the primary project definition.

Expected workflow:

```bash
tuist install
tuist generate
```

When dependencies or generated files are changed, update the corresponding Tuist manifests.

The repository should include, as appropriate:

```text
.
├── AGENTS.md
├── Project.swift
├── Tuist.swift
├── Tuist
│   ├── Package.swift
│   └── ProjectDescriptionHelpers
├── Projects
│   └── ChessTactics
├── Modules
│   ├── AppFeature
│   ├── TrainingFeature
│   ├── ChessCore
│   ├── PuzzleKit
│   ├── Persistence
│   └── DesignSystem
├── Resources
├── Tests
└── README.md
```

The exact structure may evolve, but the boundaries between app composition, chess rules, puzzle behavior, and persistence must remain clear.

### Tuist Target Guidelines

Use separate targets only when they create a meaningful architectural boundary.

Recommended initial targets:

- `ChessTacticsApp`
- `ChessCore`
- `PuzzleKit`
- `TrainingFeature`

Optional later targets:

- `Persistence`
- `StatisticsFeature`
- `ReviewFeature`
- `DesignSystem`

Do not over-modularize the first runnable version.

### Dependency Direction

Dependencies should generally flow as follows:

```text
ChessTacticsApp
  └── TrainingFeature
        ├── PuzzleKit
        └── ChessCore
```

Later:

```text
ChessTacticsApp
  ├── TrainingFeature
  ├── ReviewFeature
  └── StatisticsFeature

Feature modules
  ├── PuzzleKit
  ├── ChessCore
  ├── Persistence
  └── DesignSystem
```

Low-level modules must not import feature modules.

`ChessCore` must not depend on SwiftUI, SwiftData, or application-specific UI code.

---

## Architecture

Keep chess rules and puzzle behavior independent from UI.

Recommended responsibilities:

### ChessCore

Responsible for chess-domain behavior:

- Board representation
- Pieces and colors
- Squares
- FEN parsing
- Move representation
- UCI move conversion
- Applying moves
- Legal-move validation
- Check and checkmate detection, when required

Example concepts:

```swift
struct Square: Hashable, Sendable {
    let file: Int
    let rank: Int
}

struct ChessMove: Equatable, Sendable {
    let from: Square
    let to: Square
    let promotion: PieceType?
}
```

### PuzzleKit

Responsible for puzzle-specific behavior:

- Puzzle model
- Puzzle line
- Current expected move
- Puzzle session state
- Correct and incorrect answer handling
- Opponent move playback
- Puzzle completion
- Future review scheduling

Example model:

```swift
struct Puzzle: Identifiable, Codable, Sendable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int?
    let themes: [PuzzleTheme]
}
```

### TrainingFeature

Responsible for the training user interface:

- Chessboard presentation
- Piece selection
- Drag or tap interaction
- Move highlighting
- Feedback display
- Loading the current puzzle
- Connecting UI events to the puzzle session

### Persistence

When introduced, responsible for:

- Puzzle attempts
- Review state
- Daily activity
- Statistics
- SwiftData model definitions
- Repository implementations

Do not let SwiftData models leak through the entire application. Prefer repository or store abstractions at feature boundaries.

---

## Puzzle Session State

Do not model the training screen with many unrelated Boolean properties.

Use an explicit state machine.

Recommended state:

```swift
enum PuzzleSessionState: Equatable, Sendable {
    case loading
    case waitingForMove
    case opponentMoving
    case incorrectMove
    case solved
    case showingSolution
}
```

Expected flow:

```text
loading
  ↓
waitingForMove
  ↓
user makes a move
  ├── incorrect
  │     ↓
  │   incorrectMove
  │     ↓
  │   waitingForMove
  │
  └── correct
        ├── more moves remain
        │     ↓
        │   opponentMoving
        │     ↓
        │   waitingForMove
        │
        └── line complete
              ↓
            solved
```

The opponent move should be applied automatically after a short UI-safe transition. Business logic must not depend on animation timing.

---

## Data Source

Lichess puzzle data may be used as the source dataset.

The raw dataset must not be loaded directly by the mobile app.

Preferred pipeline:

```text
Lichess puzzle CSV/Zstandard archive
  ↓
Offline import script
  ↓
Filter and normalize puzzles
  ↓
Generate a compact mobile dataset
  ↓
Bundle the dataset with the app
```

Useful fields include:

- Puzzle ID
- FEN
- Move sequence
- Rating
- Rating deviation
- Popularity
- Number of plays
- Themes
- Opening tags, when useful

Always preserve required attribution and license information.

Do not add the entire raw Lichess database to the Git repository.

---

## Tactical Themes

Initial theme support may include:

- Fork
- Pin
- Skewer
- Discovered attack
- Sacrifice
- Mate
- Defensive move
- Endgame

Theme names in the domain layer should be stable identifiers rather than display strings.

Example:

```swift
enum PuzzleTheme: String, Codable, CaseIterable, Sendable {
    case fork
    case pin
    case skewer
    case discoveredAttack
    case sacrifice
    case mate
    case defensiveMove
    case endgame
}
```

Localization belongs in the presentation layer.

---

## Review Rules

A simple review system is preferred before introducing a sophisticated spaced-repetition algorithm.

Initial rules may be:

- Incorrect answer: review tomorrow
- First successful review: review after 3 days
- Second successful review: review after 7 days
- Any later incorrect answer: reset to review tomorrow

Review scheduling should be isolated behind a dedicated type so that it can be replaced later.

Example:

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

## First Runnable Version

This is the highest-priority implementation milestone.

Do not start statistics, streaks, filters, accounts, cloud synchronization, subscriptions, AI explanations, or large puzzle imports until this version works end to end.

### Required Scope

Implement exactly one hard-coded tactical puzzle.

The app must:

1. Launch successfully from the Tuist-generated workspace.
2. Load one hard-coded FEN position.
3. Render an 8×8 chessboard.
4. Display the pieces from the FEN position.
5. Allow the user to select and move a piece.
6. Support either:
   - tap a piece, then tap a target square; or
   - drag a piece to a target square.
7. Convert the user move into UCI notation.
8. Compare the move with the expected puzzle move.
9. Display visible correct or incorrect feedback.
10. Automatically apply the opponent's next move after a correct move.
11. Continue until the hard-coded tactical line is complete.
12. Display a solved state when the full line is completed.
13. Allow the puzzle to be restarted.

### Explicit Non-Goals

The first runnable version must not require:

- SwiftData
- A production puzzle database
- User accounts
- Network requests
- Stockfish
- Full PGN import
- Puzzle rating changes
- Streak tracking
- Theme filtering
- Sound effects
- Haptics
- App Store purchase support
- CloudKit
- Analytics
- Localization beyond basic string readiness

### Suggested Hard-Coded Model

```swift
let samplePuzzle = Puzzle(
    id: "sample-001",
    fen: "<VALID_FEN>",
    moves: [
        "<USER_UCI_MOVE>",
        "<OPPONENT_UCI_MOVE>",
        "<USER_UCI_MOVE>"
    ],
    rating: nil,
    themes: [.fork]
)
```

The move sequence must clearly define whose turn it is from the FEN.

Add a unit test proving that:

- the FEN side to move is interpreted correctly;
- the expected first move is recognized;
- an incorrect UCI move is rejected;
- the puzzle reaches `solved` after the complete line.

### Acceptance Criteria

The milestone is complete only when:

```text
tuist generate
```

successfully generates the project, and the app can be launched in an iOS Simulator with the full hard-coded puzzle flow working.

The user must be able to solve the puzzle without editing source code or using debug controls.

---

## Implementation Order

Follow this order unless a task explicitly changes it:

### Phase 1: Project Bootstrap

- Add Tuist configuration
- Generate the app target
- Add minimal module structure
- Confirm simulator launch
- Add CI-friendly build command

### Phase 2: Chess Representation

- Define piece, color, square, and move types
- Parse the required FEN subset
- Render the parsed board
- Convert user moves to UCI

### Phase 3: Interaction

- Select a piece
- Show selected square
- Move to a destination square
- Reject interactions when the session is not waiting for input

### Phase 4: Puzzle Flow

- Add the hard-coded puzzle
- Compare moves
- Show correct and incorrect feedback
- Apply opponent moves
- Detect puzzle completion
- Support restart

### Phase 5: Tests and Cleanup

- Add focused unit tests
- Remove temporary debug code
- Confirm Tuist generation from a clean checkout
- Document build and run commands

Only after Phase 5 should broader MVP work begin.

---

## Coding Standards

### Swift

- Use Swift's strict concurrency model where practical.
- Prefer value types for domain models.
- Mark domain types as `Sendable` when valid.
- Avoid force unwraps.
- Avoid global mutable state.
- Use descriptive names.
- Keep functions small and focused.
- Keep UI state on the main actor.
- Do not use arbitrary delays to fix state bugs.
- Use dependency injection rather than hidden singletons.

### SwiftUI

- Keep views declarative.
- Move non-trivial game and puzzle logic out of views.
- Avoid very large view bodies.
- Give stable identity to chess pieces and squares.
- Keep animation separate from domain mutation.
- Ensure the board remains usable on different iPhone sizes.
- Support both light and dark appearance unless explicitly deferred.

### Error Handling

- Fail clearly when bundled puzzle data is malformed.
- Prefer typed errors.
- Do not silently replace invalid chess data with an empty board.
- Development builds may use assertions for impossible internal states.
- User-facing builds must present recoverable errors appropriately.

---

## Testing Strategy

Prioritize domain tests over snapshot-heavy UI tests.

Initial tests should cover:

- FEN parsing
- Side to move
- Square conversion
- UCI conversion
- Correct move handling
- Incorrect move handling
- Opponent move advancement
- Puzzle completion
- Puzzle restart

Later tests may cover:

- Legal moves
- Castling
- En passant
- Promotion
- Review scheduling
- Persistence
- Statistics

A feature is not complete merely because the UI appears correct. Core state transitions must be testable without launching SwiftUI.

---

## Commands

Expected commands should be kept current in the repository README.

Typical commands:

```bash
tuist install
tuist generate
tuist test
```

A clean build should also be possible with an `xcodebuild` command against the generated workspace or project.

Do not commit user-specific Xcode state.

Generated project files should follow the repository's chosen Tuist version-control policy.

---

## Out of Scope Until Requested

Do not proactively implement:

- Online chess games
- Matchmaking
- Chat
- Friends
- Public leaderboards
- Social feeds
- User-generated puzzles
- Full-game Stockfish analysis
- AI-generated coaching
- Server-side accounts
- Cross-device synchronization
- Subscription billing
- Advertising
- Complex gamification
- Android support
- Web support

These may be considered after the offline tactical training loop is stable.

---

## Agent Behavior

When making changes:

1. Read this file first.
2. Inspect existing architecture before adding new abstractions.
3. Preserve Tuist as the project source of truth.
4. Keep changes limited to the requested task.
5. Do not expand the product scope without explicit instruction.
6. Add or update tests for domain behavior.
7. Run the relevant generation, build, and test commands.
8. Report what changed, what was verified, and any remaining limitation.

When requirements are ambiguous, prefer the smallest implementation that advances the first runnable version.

The first priority is always a working chess tactic loop, not architectural perfection.
