# Wakelatch: plan (iOS only)

Free, MIT, no ads, no accounts, no network code. You set two times: **Ideal** (when you'd like to be up) and **Deadline** (when you must be up). Wakelatch rings around and between them, and an alarm stays "latched" until you finish a challenge.

Name check (Nov 2026): no app, product or GitHub project called Wakelatch turned up. Aubade, Rousewell, Wakeward and FirstLight are all taken by alarm apps.

---

## 1. How SuperAlarm enforces missions on iOS

There's no single trick. It stacks several layers, each covering a different way out:

| Escape route | How SuperAlarm-style apps close it | Source |
|---|---|---|
| Tap Stop on the system alarm | Can't be removed. Instead, Stop opens the app into the challenge, and if the challenge isn't finished another alarm rings ~60 s later, repeating (ByeBed: up to 10 times over 15 min) | ByeBed comparison; JHOOX AlarmKit write-up |
| Phone on silent / Focus / app force-quit | AlarmKit (iOS 26+): the system holds the alarm, so it rings through silent mode and every Focus, and survives force-quit and restart | Apple AlarmKit docs; Wakeward support page |
| Swipe out of the app mid-challenge | The next guard alarm is already scheduled in AlarmKit, so leaving the app doesn't stop anything | same |
| Delete the app while it rings | Screen Time API: `ManagedSettingsStore().application.denyAppRemoval = true` while ringing, cleared after the challenge. Needs Apple's Family Controls entitlement and explicit user opt-in | SuperAlarm developer's blog post (2024) |
| Older iOS (17–25) | Silent background audio loop to keep the app alive + a burst of local notifications as backup. Fragile and an App Review risk | flutter `alarm` package, Stack Overflow, WakeHard repo |

**Wakelatch approach:** iOS 26+ only (AlarmKit), so we skip the fragile pre-26 audio hacks entirely.

Limits no app can get around (we document them honestly):
- Turning the phone off stops everything.
- AlarmKit can't set volume; it plays at ringer volume. Attention Aware Features lowers it when you look at the phone.
- Alarms from apps that are hidden or locked behind Face ID silently fail (Apple-documented).
- There's a per-app cap on scheduled AlarmKit alarms (number not published). The guard chain must fit under it. **Verify in the spike.**

---

## 2. Research basis (from round 1)

- Deep-sleep awakenings cause the worst grogginess (Hilditch & McHill 2019).
- ~30 min of gentle pre-alarms didn't hurt cognition in habitual snoozers and avoided deep-sleep wakes (Sundelin 2024). A small study found frequent snoozes raise grogginess (Ogawa 2022), so keep the pre-window short with few alarms.
- Melodic tones beat harsh beeps (McFarlane 2020).
- Phone sleep-stage detection is unreliable (Fino 2020), so the core is a fixed schedule.
- No evidence that challenges remove grogginess. Their job is to stop autopilot dismissal and keep you awake long enough for it to pass. Grogginess mostly clears within ~15–30 min, which is why the awake checks matter.

---

## 3. Schedule

```
Ideal − 20m ─── Ideal ───────────────────── Deadline ── +15m
  soft nudges   main alarm (latched)         final       awake checks
                re-rings if not done         (latched,
                                              no snooze)
```

1. **Soft nudges** at Ideal −20 and −10 min: quiet melodic AlarmKit alarm, plain Stop (no challenge).
2. **Main alarm** at Ideal: latched. Snooze allowed, each snooze shorter, next challenge harder.
3. **Re-rings** between Ideal and Deadline at shrinking intervals, last one clamped to Deadline.
4. **Deadline alarm**: latched, no snooze, hardest challenge.
5. **Awake checks** 5 and 12 min after the challenge is done: an AlarmKit alarm whose only job is "tap I'm up within 60 s". Miss it → full latched alarm again.

### The latch, concretely
When a latched alarm is due, Wakelatch pre-schedules a **guard chain** in AlarmKit: the alarm plus N follow-ups every 60–90 s. All of them are on the system's books before you're even awake.
- Stop on any ring → stop intent opens Wakelatch to the challenge screen; the challenge screen plays its own looping alarm audio.
- Challenge finished → cancel the rest of the chain, clear `denyAppRemoval`, schedule awake checks.
- Challenge not finished → the next link in the chain rings anyway.
- Emergency exit: two "skips" per month, each needs typing a long phrase. Prevents getting trapped (e.g. a bug or a broken camera).

The scheduler is a pure Swift module (`times + settings → [AlarmEvent]`) with unit tests for DST, midnight crossing, Ideal = Deadline, timezone change, and staying under the AlarmKit cap.

---

## 4. Challenges (no QR codes)

All on-device, nothing leaves the phone.

| Challenge | How | Notes |
|---|---|---|
| Math | Typed answers on a keypad, no multiple choice. Difficulty scales with stage | Default for main alarm |
| Memory | Repeat a growing tile pattern | |
| Type a phrase | Exact match, trailing-space tolerant (a SuperAlarm review hit this bug) | |
| Eyes open (Face ID camera) | ARKit face tracking on the TrueDepth camera; eyes must stay open (blink blend shapes below threshold) for 30–60 s | SuperAlarm's "keep eyes open" mission. Vision face landmarks as fallback on devices without TrueDepth |
| Read aloud | Speech framework, on-device recognition, read a random sentence | Voice gets the brain going |
| Shake | Core Motion, N strong shakes | Easy, good for nudges/awake checks |
| Steps | Core Motion pedometer, N steps | Gets you out of bed without a QR code |
| Squats / push-ups | Vision body-pose, count reps | Stretch goal |

Default setup: Main = Math, Deadline = Eyes open + Steps, Awake check = one tap.

---

## 5. Stack

- Swift 6, SwiftUI, iOS 26.2+ minimum (check whether the AlarmKit stop-button API change in 26.2 matters).
- AlarmKit, App Intents (stop/secondary intents), ActivityKit (Live Activity for the ringing/countdown UI, required by AlarmKit for countdowns), ARKit, Vision, Speech, Core Motion, FamilyControls + ManagedSettings.
- SwiftData for alarms and history. No network entitlement used.
- XcodeGen project, MIT license, public GitHub repo.
- Needs: paid Apple developer account ($99/yr) and Apple's approval for the Family Controls entitlement (request form). Without it, everything works except blocking app deletion.

---

## 6. Phases

| Phase | Scope | Done when |
|---|---|---|
| 0. Spike (1–2 days) | Throwaway app on a real iPhone. Verify: (a) AlarmKit per-app cap, (b) stop intent can open the app straight into a screen, (c) guard chain keeps ringing after Stop/force-quit/restart, (d) denyAppRemoval works with the dev entitlement | All four answered with notes |
| 1. Core | Scheduler module + tests, two-time setup UI, nudges, latched main/deadline alarms with guard chain, Math + Type challenges, awake checks, emergency skips | 14 mornings of real use with no missed or un-stoppable alarm |
| 2. Challenges | Eyes open, Read aloud, Shake, Steps, Memory; melodic sound set (own or CC0) | Each challenge has unit tests for its pass logic |
| 3. Polish | Onboarding (permissions, "don't hide/lock this app", ringer volume check), stats ("up by Ideal 5/7 days"), widgets, Live Activity design | — |
| 4. Release | Family Controls entitlement approved, App Store review, MIT repo public | Live on App Store |

Test matrix before each release: screen locked overnight, silent switch, Sleep Focus, force-quit, reboot before alarm, Low Power Mode, AirPods connected, phone call during alarm, DST forward/back, timezone change, app deleted attempt while ringing.

---

## Sources

- SuperAlarm dev on denyAppRemoval: https://tinycoder.pika.page/posts/preventing-app-removal-on-ios
- ByeBed vs SuperAlarm (re-ring after Stop): https://byebed.com/blog/byebed-vs-superalarm
- AlarmKit Stop button can't be blocked, guard-alarm workaround: https://www.jhoox.com/blog/alarmkit-stop-button-blocker
- AlarmKit sample + docs: https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit
- WWDC25 "Wake up to the AlarmKit API": https://developer.apple.com/videos/play/wwdc2025/230
- AlarmKit limits (volume, hidden apps, stuck Live Activity): https://mwsupplylimited.github.io/wakeward/index.html
- Pre-iOS 26 background-audio approach: https://github.com/gdelataillade/alarm , https://github.com/javuls/WakeHard
- Sleep research sources: see round-1 list (Hilditch 2019, Sundelin 2024, Ogawa 2022, McFarlane 2020, Fino 2020)
