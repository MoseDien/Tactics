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
  `AppDependencies` composition root, `RoundTracker`, `TacticsPacing`.
  Animation timing lives in the board view, never in the domain.

## Product rules

- The app is offline-first: one bundled chunk (`puzzle-0000.json`, 1000
  puzzles, in the TacticsData bundle) plus on-demand chunk downloads when the
  untried pool can't fill a round (the only sanctioned network behavior).
- Settings exposes the same next-chunk delivery path manually. When the
  untried pool has 50 or more puzzles, its always-tappable control explains
  the threshold instead of silently disabling; its loading indicator remains
  local to the control, not a screen replacement.
- Lichess lines are machine-first: `moves[0]` auto-plays, then the player
  starts at `moves[1]` and turns alternate.
- During an active puzzle Hint reveals the expected move visually but never
  auto-plays it. Once the puzzle is complete, the same control opens a
  read-only review of that puzzle.
- Round review navigation is not undo. After a Play round is complete, `Next
  puzzle` enters Review mode and loops through the current round.
- `Next round` remains tappable during its cooldown: it shows the remaining
  wait time, and the view model must reject an early start.
- When a foreground refresh finds an expired round window, show the Next
  round CTA regardless of the current board-feedback state.
- On a cold launch with an expired persisted round, start the newly available
  Play round directly; the Next round CTA is for foregrounding an existing UI.
- Review may record puzzle progress, but must never update the user's Rating.
- Keep the normal training screen usable on iPhone SE without scrolling;
  retain `ScrollView` only as a Dynamic Type/accessibility fallback.
- Do not display `Solved` or `Failed` counters in the training UI.
- Rating starts at 1500, uses the isolated policy in
  `PuzzleKit/RatingPolicy.swift`, and persists locally (UserDefaults scalar +
  one SwiftData snapshot per completed round).

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
