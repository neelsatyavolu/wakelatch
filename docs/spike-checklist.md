# Phase 0 spike: iPhone checklist

The spike app (`WakelatchSpike`, shown as "Wakelatch") answers four questions that only a real iPhone on iOS 26.2+ can answer. Fill in the Result lines and keep the log (Log → Share log) for each run.

## Setup

1. `brew install xcodegen` (once), then `xcodegen generate` in the repo root.
2. Open `Wakelatch.xcodeproj`, select the `WakelatchSpike` scheme and your iPhone.
3. Signing: team VTQW687WBQ. The Family Controls capability works in development builds without Apple's approval.
4. Run. Allow alarms when asked.

## (a) How many alarms can one app schedule?

Cancel any chain, tap **Find the alarm limit**. It schedules alarms a month out until AlarmKit refuses (up to 300), then cancels them.

Result (2026-11-12, TestFlight 0.1.0, owner's iPhone): no refusal up to 300.

## (b) Does Stop open the app straight to the challenge?

Arm a latch (first ring in 30 s, 2 guard rings). Lock the phone. When it rings, tap **Stop** on the lock screen. Note whether the app opens to the challenge, or only after unlocking, or not at all. Repeat with the **Solve** button. The log shows "Stop intent ran" / "Solve intent ran".

Result (Stop): lock screen shows a red Solve button and Slide to stop. Slide to stop → Face ID → app opens to the math problem. Ringing stopped on Stop; a ring came back ~10 s after unlocking (probably the next guard ring); solving ended it.
Result (Solve): not tried separately.

## (c) Does the guard chain survive Stop, force-quit and reboot?

For each, arm 5 guard rings at 60 s, let ring 1 fire, then:
- tap Stop and do nothing: do rings 2–6 still fire?
- swipe the app away (force-quit): do the remaining rings fire?
- restart the phone before ring 1: do all rings fire after boot?
- solve the challenge: do the remaining rings stop?

Results: Stop and walk away → guard ring 1 sounded ~45 s later. Force-quit → still rang. Reboot before ring → rang after boot. Alarm also rang on Apple Watch.

## (d) Can the app block its own deletion while latched?

Turn on **Block deleting the app**, approve Screen Time, arm a latch. Try to delete the app from the home screen. Solve the challenge, then try again.

Not testable in TestFlight builds until Apple approves Family Controls distribution.

## Also note

- Ringer volume vs. the alarm's loudness; whether Attention Aware lowered it.
- Anything AlarmKit showed that the spike's UI didn't expect (system alert layout, Live Activity).
