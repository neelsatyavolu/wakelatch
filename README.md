# Wakelatch

A free iOS alarm that won't let go until you're up. Set two times, **Ideal** and **Deadline**. Wakelatch nudges you before Ideal, then latches the main and deadline alarms: they keep ringing until you finish a challenge (math, keeping your eyes open, walking, and more).

No ads, no accounts, no network code. MIT licensed. Requires iOS 26.2 or later (AlarmKit).

**Status:** Phase 0. The repo holds a test app that checks what AlarmKit and Screen Time allow on a real iPhone. The plan is in [docs/plan.md](docs/plan.md); the device checks are in [docs/spike-checklist.md](docs/spike-checklist.md).

## Layout

- `Packages/WakelatchCore`: pure Swift logic (guard chain, math challenges), tested with `swift test`.
- `Spike/`: the Phase 0 test app.
- `PRODUCT.md`: who it's for and what it must do.

## Build

```sh
brew install xcodegen
xcodegen generate
open Wakelatch.xcodeproj
```

Core tests: `cd Packages/WakelatchCore && swift test`.

## License

MIT, see [LICENSE](LICENSE).
