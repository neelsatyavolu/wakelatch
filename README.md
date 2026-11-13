# Wakelatch

A free iOS alarm that won't let go until you're up.

Set two times: **Ideal**, when you'd like to be up, and **Deadline**, when you have to be. Wakelatch nudges you softly before Ideal. From Ideal it rings every few minutes (Stop snoozes). From the Deadline it rings every minute and only a challenge stops it: math, typing a sentence, keeping your eyes open, walking, or shaking the phone. Two short "still up?" checks follow a few minutes later.

- Rings through silent mode and Focus, on Apple Watch too, even if the app is closed or the phone restarts (Apple's AlarmKit).
- Leave it open on the charger in **Bedside mode** for a full-screen alarm with its own sound.
- Two emergency skips a month, for when a challenge can't be done.
- No ads, no accounts, no analytics, no network code. MIT licensed. Requires iOS 26.2 or later.

Privacy policy: [docs/privacy.md](docs/privacy.md). Support: [GitHub issues](https://github.com/neelsatyavolu/wakelatch/issues).

## Layout

- `App/`: the iOS app (SwiftUI).
- `Packages/WakelatchCore/`: pure Swift schedule and challenge logic, tested with `swift test`.
- `AppUITests/`: end-to-end mornings against real AlarmKit in the simulator.
- `DESIGN.md`, `PRODUCT.md`: design system and product brief. `docs/plan.md`: research and plan.

## Build

```sh
brew install xcodegen
xcodegen generate
open Wakelatch.xcodeproj
```

- Core tests: `cd Packages/WakelatchCore && swift test`
- UI tests (each waits for real alarms, a few minutes): `xcodebuild test -project Wakelatch.xcodeproj -scheme Wakelatch -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- TestFlight upload: `scripts/testflight.sh` (credentials from 1Password via the gitignored `scripts/testflight.local.sh`)

## License

MIT, see [LICENSE](LICENSE).
