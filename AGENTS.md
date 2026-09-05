# DailyTactics agent instructions

Read this file before changing the project. Keep work scoped to the requested
feature and preserve the existing offline iOS SwiftUI product direction.

## Source of truth

- 当前只开发 iOS；Android 暂停，直到 iOS 版本完成并稳定。

- `ios/Project.swift` and `ios/Tuist.swift` define the Xcode project.
- Generate from `ios/` with `mise x tuist@4.197.3 -- tuist generate`.
- Never use the generated `.xcodeproj` as the primary project definition.
- Preserve Bundle ID `com.dienbell.tactics`.
- The current product flow is documented in [docs/BUSINESS_LOGIC.md](docs/BUSINESS_LOGIC.md).

## Boundaries

- `ChessCore`: pure chess domain types; no SwiftUI or SwiftData.
- `PuzzleKit`: puzzle data, session state, policies, repository ports; no
  UI/storage imports.
- `TacticsData`: SwiftData models, repositories, the bundled puzzle chunk,
  chunked remote delivery, UserDefaults stores. The only module importing
  SwiftData.
- `DailyTactics` (app): SwiftUI features (Tactics/Settings/Onboarding), the
  `AppDependencies` composition root, `BatchTracker`, `TacticsPacing`.
  Animation timing lives in the board view, never in the domain.

## Product rules

- The app is offline-first: one bundled chunk (`puzzle-0000.json`, 1000
  puzzles, in the TacticsData bundle) plus on-demand chunk downloads when the
  untried pool can't fill a batch (the only sanctioned network behavior).
- Lichess lines are machine-first: `moves[0]` auto-plays, then the player
  starts at `moves[1]` and turns alternate.
- Hint reveals the expected move visually but never auto-plays it.
- Batch review navigation is not undo. After a Play batch is complete, `Next
  puzzle` enters Review mode and loops through the current batch.
- Review may record puzzle progress, but must never update the user's Rating.
- Keep the normal training screen usable on iPhone SE without scrolling;
  retain `ScrollView` only as a Dynamic Type/accessibility fallback.
- Do not display `Solved` or `Failed` counters in the training UI.
- Rating starts at 1500, uses the isolated policy in
  `PuzzleKit/RatingPolicy.swift`, and persists locally (UserDefaults scalar +
  one SwiftData snapshot per completed batch).

## Change checklist

1. Inspect the existing architecture and current user changes.
2. Update domain tests for behavior changes.
3. Run Tuist generation and the full test suite.
4. Compile a small-screen iOS Simulator destination for UI changes.
5. Update `README.md`, `CLAUDE.md`, and this file when behavior or workflows
   change.

## Commands

```sh
cd ios
mise x tuist@4.197.3 -- tuist generate
xcrun xcodebuild test -project DailyTactics.xcodeproj -scheme DailyTactics \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

`tuist test` resolves only workspace-level schemes, which this project no
longer generates — run xcodebuild against the generated project instead.

Avoid committing generated Xcode state, local databases, raw Lichess archives,
or machine-specific settings.
