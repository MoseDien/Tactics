# DailyTactics

An iOS-only, offline SwiftUI app for solving focused chess tactics.

Chess piece artwork uses the Lichess `chessnut` SVG set by Alexis Luengas,
licensed under Apache License 2.0. See `THIRD_PARTY_NOTICES.md`.

## MVP1

The first runnable version includes one bundled FEN puzzle and the complete
`Qe8+ Rxe8 Rxe8#` training flow. It supports tap-to-move interaction, UCI move
matching, immediate feedback, an automatic opponent reply, and puzzle restart.

## Requirements

- Xcode 16 or newer
- Tuist
- iOS 17 or newer

## Run

```sh
mise x tuist@4.197.3 -- tuist generate
open DailyTactics.xcworkspace
```

Run tests with:

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
