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
- `PuzzleKit`: puzzle data and line/session state; no UI/storage imports.
- `Persistence`: SwiftData progress and local Rating storage/policy.
- `Features/Tactics`: SwiftUI board, training layout, Hint, review controls,
  orientation, and view-model orchestration.

## Product rules

- The app is offline and uses bundled JSON puzzle buckets under `ios/DailyTactics/Resources/`.
- Lichess lines are machine-first: `moves[0]` auto-plays, then the player
  starts at `moves[1]` and turns alternate.
- Hint reveals the expected move visually but never auto-plays it.
- Batch review navigation is not undo. After a Play batch is complete, `Next
  puzzle` enters Review mode and loops through the current batch.
- Review may record puzzle progress, but must never update the user's Rating.
- Keep the normal training screen usable on iPhone SE without scrolling;
  retain `ScrollView` only as a Dynamic Type/accessibility fallback.
- Do not display `Solved` or `Failed` counters in the training UI.
- Rating starts at 1500, uses the isolated policy in `Persistence/Rating.swift`,
  and is persisted locally.

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
mise x tuist@4.197.3 -- tuist test
```

Avoid committing generated Xcode state, local databases, raw Lichess archives,
or machine-specific settings.
