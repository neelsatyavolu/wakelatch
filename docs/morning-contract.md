# Morning contract

This is the behaviour `MorningEngine` (in `Packages/WakelatchCore`) must implement. Each rule is written so a test can check it. Tests cite rules by number, for example `C4.2`.

Terms:
- **Morning**: one day's alarm, identified by its Ideal as a `Date`.
- **Latched ring**: main, snooze, deadline or guard. Nudges and awake checks are not latched.
- **Due**: a ring is due at `now` when `ring.date <= now`.
- **Latest due ring** of a morning: among its latched rings at or before `now`, the one with the highest level, then the greatest date. Levels never fall with date in a planned morning, so this is the latest due ring; a stray lower-level ring dated later can never lower the bar a morning must clear, or bring Snooze back after the Deadline.
- **Active morning**: defined in rule L1.
- **Target**: `EngineState.target`, the rings the engine wants AlarmKit to hold.
- **Session**: `SessionState`, in memory only.

Owner decisions D1, D2 and D3 are binding and are restated where they apply.

## 1. Timing (T)

T1. All spacing is in seconds and comes from `PlanTiming`. Engine logic never reads `Date.now`, `Calendar.current` or the device volume. Time, calendar, settings, audibility and cover visibility always arrive in events.

T2. `PlanTiming.production(options)`:

| Field | Value |
|---|---|
| nudges | Ideal-20 min and Ideal-10 min when `options.nudges`, none otherwise |
| snooze spacing | `options.snoozeMinutes` (at least 3 min), widened to `ceil(window / 24)` so a morning has at most 24 snoozes |
| snooze dropped | when it is less than 60 s before the Deadline |
| guards | every 60 s after the Deadline, up to 60 min after it: 60 guards (D2). `options.guardRings` is ignored |
| grace | 10 min after the last guard |
| awake checks | solve+5 min and solve+12 min, each followed by 3 guards 60 s apart |
| awake-check expiry | 15 min after the ring's date |
| route max age | 120 s |
| nudge screen cap | 5 min |
| Released keeps screen awake | 60 s |

T3. `PlanTiming.compressed` (UI tests, launch time L, Ideal = L + 60 s, `windowOverride` = 120 s): nudges at Ideal-40 s and Ideal-20 s, snoozes at +40 s (L1) and +80 s (L2), deadline at +120 s, guards at +145, +170 and +195 s, grace 30 s, awake checks at solve+30 s and solve+70 s each with 2 guards 20 s apart. Setting `nudgeOffsets = []` gives the no-nudge profile.

T4. Levels: nudges and awake checks are level 0. Main is level 1. A snooze at offset `o` from Ideal is level 1 when `2 * o <= window` and level 2 otherwise. Deadline and guards are level 3.

T5. Each latched ring carries the challenge kind from the settings at the moment it was planned: the snooze kind for main and snooze rings, the deadline kind for the deadline and guards. Nudges and awake checks carry none. Changing a kind in settings never changes a ring already in target for an active morning.

T6. A window longer than 180 min is refused (`PlanError.windowTooLong`). A window of 0 gives no main and no snoozes, only the deadline and its guards.

T7. Ideal on a day is computed with the injected calendar. An Ideal inside a spring-forward gap moves to the next valid time. An Ideal in a repeated fall-back hour uses the first occurrence. No morning has two rings with the same id.

## 2. Ring identity (I)

I1. `Ring.id == RingIdentity.id(morning:kind:date:group:level:challenge:)`, a version-5 UUID over `"v2|<morning epoch>|<kind>|<date epoch>|<group or ->|<level>|<challenge or ->"`.

I2. Building the same morning twice with the same settings gives identical ids. Any change to morning, kind, date, group, level or challenge kind gives a different id.

I3. Every ring's full contents (kind, level, morning, group, challenge) travel in the AlarmKit metadata, so `SystemAlarm.ring` can rebuild it. Since every one of them is hashed into the id (I1), an id in AlarmKit's table always carries the metadata target has for it: changing a kind or a window gives new ids, which the next pass schedules while it cancels the old ones.

## 3. Which mornings are armed (A)

A1. `upcomingMornings` returns Ideals strictly after `now`. A morning whose first nudge has passed but whose Ideal is still ahead is included, with only its future rings scheduled.

A2. The calendar day of the active morning never yields a second morning. No morning is armed before the active morning's `endsBy`.

A3. With repeat days set, up to `armedMornings` (3) mornings are armed, on matching weekdays only, searched over 15 days. A morning under way counts toward them: while one is active, `armedMornings - 1` future mornings are armed, so opening the app mid-morning never pushes the budget trim (A7) into a morning that was held whole.

A4. With repeat days empty (one-off): the first qualifying morning is stored in `oneOffMorning` when it is armed. While `oneOffMorning` is set, no other morning is armed. When that morning finishes with any outcome, the engine sets `enabled = false` in its settings, records the turn-off in the persisted `turnedOff`, and emits `.disableAlarm` straight after `.persist`. Until settings arrive with `enabled == false` (the app saved the turn-off and passed its settings on), any settings saying enabled are stale: in `settingsChanged` or when a new engine is built, they are treated as off, nothing is armed, and `.disableAlarm` is sent again (on `settingsChanged`, and on the first event of every new engine). A kill before the app saved the turn-off therefore cannot re-arm the alarm. Settings with `enabled == false` clear `turnedOff`, after which turning the alarm on arms normally.

A5. With `enabled == false`, no new morning is armed and future mornings leave target. An active morning is unaffected (D3).

A6. `pinnedMorning` (UI tests) replaces A1-A4 with that single Ideal.

A7. Budget (D2): the count of future rings in target, over all armed mornings plus awake checks, is at most 250. When over, guards are removed from the farthest armed morning first, latest guard first. The next morning to ring, the active morning and awake checks are never trimmed. If every later morning has lost all its guards and the count is still over, whole mornings are dropped, farthest first. Trimmed guards come back on the next target refresh (`launched`, `becameActive`, a settings or calendar change, or a finish), not on a plain reconcile. A morning that is under way always gets its missing guards back on the first event after it starts: they are rebuilt from its deadline ring, with the ids `MorningPlan.build` gives them, and the active morning counts as reserved, so this stays within the budget.

## 4. Morning lifecycle (L)

L1. A morning is active at `now` when its first ring in target (a nudge counts) or its Ideal is due, it is not in `finished`, and `now <= lastLatchedRing.date + grace`. If several qualify, the oldest is active. Awake checks never make a morning active. (The Ideal counts so a morning adopted with only its future rings, R2, is still under way.)

L2. `finished[m]` is set once and never changed. Outcomes: `solved` (rule C6), `skipped` (rule K1), `missed` (rule L3).

L3. A morning not in `finished` whose `lastLatchedRing.date + grace` is before `now` becomes `missed` on the next event. Its remaining rings leave target. Reconcile cancels only its alarms that are alerting; alarms of a missed morning that have not rung yet stay in AlarmKit. On an honest clock there are none, but after the device clock is moved forward they are the morning's real future rings, and setting the clock back must still find them.

L4. Every finished morning gets exactly one `MorningRecord` holding its outcome, its deadline, and `upAt` for solved mornings. Records keep the latest 60.

L5. `underWay(at:)` is non-nil exactly when `activeMorning(at:)` is non-nil, and reports the morning, its deadline and `endsBy` (last latched ring plus grace). The UI uses it to say "today's alarm is under way" (D3).

## 5. Alert buttons (B)

B1. The buttons of each system alert, from `AlertSpec.for(kind)`:

| Kind | Title | Stop | Secondary |
|---|---|---|---|
| nudge | "Wakelatch. Ideal time soon." | `.none` | none (no secondary button) |
| main, snooze | "Wakelatch. Stop to snooze." | `.none` (system snooze: the next ring is already scheduled) | "I'm up": `.openToChallenge` |
| deadline, guard | "Wakelatch. Deadline. Solve to stop." | `.openToChallenge` | "Solve": `.openToChallenge` |
| awakeCheck | "Wakelatch. Still up?" | `.confirmAwake` | "I'm up": `.confirmAwake` |

B2. `.none` sends no event. The pressed ring stops, every later ring of the morning stays in the system table, and the morning continues.

B3. `.openToChallenge` is a foreground intent. It sends `alertAction(ringID, .openToChallenge, now)`, which stores `route = PendingRoute(ringID, now)` and persists it. The route is applied by rule S1 as soon as the app is active, whether `alertAction` arrives before or after `launched`/`becameActive` or after the first tick.

B4. `.confirmAwake` is a background intent. It confirms the ring's awake-check group (rule W3) without bringing the app forward.

B5. The process state when the button is pressed (killed, suspended, foreground on home, Bedside, a sheet, or a stale challenge or Released screen in memory) does not change the outcome of B2-B4. The one exception: on a locked device where the user cancels the unlock, a foreground intent never runs. Nothing changes and the next ring still comes.

## 6. Screen priority (S)

The engine recomputes `screen` after every event. The first rule that applies wins.

S1. **Route.** If `route` is set, `now - route.at <= routeMaxAge`, the app is active, and the route's ring is latched and belongs to the active morning: open the challenge for the latest due ring (rule C1), clear `route`, and show `.challenge`. A route that is too old, belongs to a finished or non-active morning, or names an unknown ring is cleared and ignored.

S2. **Open challenge.** If `state.challenge` is set and its morning is still active: show `.challenge`, upgraded by rule C3. If its morning is finished or no longer active, clear it and continue with S3.

S3. **Awake check.** If an awake-check ring is due, not acknowledged and not expired: show `.awakeCheck(latest such ring)`.

S4. **Active morning ringing.** If the active morning has a latest due ring R:
  - R is alerting: `.ringing(R, sounding: true, snoozedUntil: nil)`. "Alerting" here reads strictly: any due latched ring of the active morning that AlarmKit reports alerting, or that the app silenced on takeover (F3) and the user has not tapped yet (`session.takenOver`), keeps the screen sounding. An older ring still going off is never shown as a silent "Snoozed until".
  - R is `session.dismissedThisVisit` (snoozed in-app during this visit): `.none`.
  - R allows snooze: `.ringing(R, sounding: false, snoozedUntil: nextLatched.date)`. This is D1: after a system Stop or an in-app Snooze, a later open shows "Snoozed until h:mm" with Start challenge, never home.
  - Otherwise (deadline or guard): `.ringing(R, sounding: false, snoozedUntil: nil)`, with Solve only.

S5. **Nudge.** If a nudge of a morning that is not finished is alerting, show `.ringing(nudge, sounding: true, snoozedUntil: nil)` and record `session.nudge`. The nudge screen stays after the alert stops, until `tapNudgeStop`, `enteredBackground`, or `nudgeScreenCap` after it first showed. Ticks alone never clear it earlier.

S6. **Released.** `session.released` shows `.released(record)`. It is cleared by `closeReleased` and `enteredBackground`, and also cleared (not just hidden) whenever S1-S5 apply, so it never comes back after an awake check or a newer ring has taken the screen (plan 1.3 rule 3, scenario R17).

S7. Otherwise `.none`.

S8. Cold equals warm. Take the same persisted `EngineState`, settings, calendar, system table and `now`. A killed app receiving `launched` and a suspended app receiving `becameActive` (after `enteredBackground`) produce the same `screen` and sound once each has received the `systemTable` event. `enteredBackground` clears `dismissedThisVisit`, `nudge`, `released`, `alerting` and `coverVisible`.

S9. `dismissedThisVisit` is cleared when a newer latched ring becomes due.

## 7. Sound, silence, sheets, idle timer (F)

F1. Sound follows the screen while the app is active. It is `.play(nudge: kind == .nudge)` for `.ringing(sounding: true)` and `.stop` for every other screen, and `.stop` whenever the app is not active (after `enteredBackground`, or before `launched` in a process an intent started). `.sound` is emitted only when the value changes.

F2. `tapSnooze(R)`, `tapNudgeStop(R)` and `tapStartChallenge(R)` always emit `.silence(R.id)`, at any volume.

F3. Takeover: when an `alerting` event moves the screen to `.ringing(sounding: true)`, the engine emits `.silence` for those ids only if `audible && coverVisible`. Otherwise the system alarm keeps ringing alongside the app.

F4. While `.challenge` shows for morning m, an `alerting` event for rings of m keeps the challenge (upgraded by rule C3). It emits `.silence` for each alerting ring of m only while the cover is visible and the challenge is in use: it was opened, or had input (`challengeActivity`, sent by the views for a keystroke, step, shake or face sample), within `MorningEngine.challengeIdleLimit` (30 s). A challenge left without input never silences: the system alarm rings over it, and the next input silences every alerting ring of m. Opening the challenge and walking away can therefore never keep the rest of the morning quiet.

F5. `.silence` is never emitted while `coverVisible == false` or while the app is not active. iOS can keep a backgrounded app running, and its cover can still "appear" there, but nobody sees it, so the system alarm must keep ringing. If a takeover was held back for that reason, `coverShown(audible:)` applies F3 then.

F6. `.dismissHomeSheets` is emitted, before any `.silence`, whenever the screen changes from `.none` to anything else, and when Bedside starts.

F7. The idle timer is disabled exactly when one of these holds: the screen is `.ringing`, `.challenge` or `.awakeCheck`; the screen is `.released` and less than `releasedKeepAwake` has passed since the solve; or Bedside is on, keep-screen-on is set, and the phone is charging. `.setIdleTimerDisabled` is emitted only when this value changes. Nothing else writes it.

F8. `becameActive` and `launched` emit `.readSystemTable`. The `systemTable` reply replaces `session.alerting`, so alarms that started alerting while the app was inactive are picked up. While the app is not active, `alerting` events and table reads leave `session.alerting` empty: a suspended app misses the update that an alert stopped, so a ring seen in the background (a nudge in particular, S5) must never stay on screen when the app opens.

## 8. Challenge lifecycle (C)

C1. Opening a challenge (from `tapStartChallenge` on the latest due ring, or from a route) sets `state.challenge = requiredChallenge(latestDue)`: the ring's snapshotted kind at the ring's level, or math if that kind was marked unavailable for this challenge. The challenge is persisted.

C2. `tapStartChallenge` on a ring that is not the latest due ring of the active morning opens the challenge for the latest due ring instead.

C3. Upgrade. While a challenge is open, if the latest due ring has a higher level or a different snapshotted kind than `challenge.ring`, the challenge is replaced by `requiredChallenge(latestDue)`. The new ring id resets the view's progress. Same level and kind keeps the challenge and its progress.

C4. `challengeUnavailable(kind)` while the open challenge has that kind replaces it with math at the same level and ring.

C5. A challenge survives kill and relaunch. After `launched`, S2 shows it, upgraded by C3 if needed.

C6. `solved(ringID)` is accepted only when all of these hold (the latest due ring is the bar, so a stray lower-level ring never lowers it):
  - `state.challenge?.ring.id == ringID`;
  - the ring's morning is active and not finished;
  - `challenge.level >= latestDue.level`;
  - the kind matches the latest due ring's snapshot (or math by C4).

  When accepted, in this one transition, the engine:
  1. sets `finished[m] = .solved` and appends the record with `upAt = now`;
  2. removes every remaining ring of m from target and emits `.cancel` for each future one;
  3. with awake checks on, adds the awake-check rings to target and emits `.schedule` for each;
  4. clears `challenge` and `route`;
  5. sets `session.released` and shows `.released`.

C7. A `solved` that is not accepted changes nothing (no effects besides an upgrade by C3). A second `solved` for the same morning is a no-op: one record, one set of awake checks.

C8. `tapSnooze` on a deadline or guard ring is refused and changes nothing.

C9. `tapSnooze(R)` on the latest due snoozable ring adds R to `acknowledged`, sets `dismissedThisVisit = R`, emits `.silence(R.id)` and shows `.none`. The next ring stays scheduled.

## 9. Emergency skip (K)

K1. `skip(ringID)` is accepted when the ring's morning is active and not finished and `skips.remaining(at: now) > 0`. It records the skip in the ledger, sets `finished[m] = .skipped`, removes the morning's rings from target, emits `.cancel` for each future one, clears the challenge, schedules no awake checks and shows `.none`.

K2. There are 2 skips per Gregorian calendar month, counted in the injected calendar's time zone whatever calendar system the device uses (switching to a Hebrew, Islamic or Chinese calendar never resets the count). A third skip in the same month is refused, and the morning continues unchanged. The count resets on the first day of the next Gregorian month.

## 10. Awake checks (W)

W1. Awake checks are added to target only by C6, and only when `settings.awakeChecks` is on. Group g is a check at `solvedAt + awakeOffsets[g]` followed by `awakeGuards` guards `awakeGuardSpacing` apart.

W2. A due, unconfirmed, unexpired awake-check ring shows `.awakeCheck` (rule S3). It plays sound only while it is alerting.

W3. Confirming a group (`tapImUp` on any of its rings, or `alertAction(.confirmAwake)` from either system button) adds every ring of the group to `acknowledged`, removes them from target, and emits `.cancel` for each. The other group is unaffected.

W4. Awake-check rings older than `awakeCheckExpiry` leave target without any action from the user.

W5. Reconcile never drops an awake check that is in target. Opening the app from an awake-check alert leaves the check on screen until it is confirmed.

## 11. Settings and calendar changes (D3)

G1. `settingsChanged` and `calendarChanged` rebuild target for every morning except the active one. The active morning's rings, levels, dates and snapshotted kinds stay exactly as they were, and it keeps ringing until solved, skipped or missed.

G2. Turning the alarm off during an active morning removes only future mornings. `underWay` stays non-nil, so the UI can say today's alarm is still on.

G3. Moving Ideal during an active morning never creates a second morning on the same calendar day (A2). The new times apply from the next qualifying day.

G4. A time-zone change (`calendarChanged`) rebuilds future mornings in the new zone's local times.

## 12. Reconcile (R)

R1. The engine emits `.readSystemTable` on `launched`, `becameActive`, after any event that changes target, on the first event a new engine receives, whatever it is (a background intent can start a process that never receives `launched`), on the first `tick` after the process's first pass (one confirming read: an AlarmKit call a killed process had already sent can land just after the new process's first read), and while `failedSchedule` is not empty, at most once every `MorningEngine.scheduleRetryInterval` (60 s) (R4). A `systemTable` event never asks for another read. On `systemTable(alarms, now)` it runs `Reconciler.plan(target:system:pending:activeMorning:now:)`.

R2. Order of one pass:
  1. adopt: system alarms whose id is not in target, whose metadata ring is latched, belongs to the active morning and fires after `now`, are added to target, except:
     - an old version of a target ring (same kind and date as one, a different id) is never adopted;
     - a ring that would lower the bar is never adopted: one with a lower level than an earlier-dated latched ring of the same morning (in target or the table), such as a snooze left over from a longer window dated after the new Deadline;
     - when target holds the morning's deadline ring, only guards dated after it and no later than target's last latched ring of that morning are adopted, so a second plan of the same morning is never adopted.
     When target has no active morning and this state has never run a pass (`firstPass == nil`: a new install, or state lost or reset), the active morning for adoption is the oldest morning in the table that has no ring in target, is not finished, has started (`morning - largest nudge offset <= now`), is no older than the longest possible morning, and whose last latched alarm plus grace is not past. Its future latched alarms are adopted instead of cancelled. `firstPass` is set by the first pass.
  2. `.persist`, with every id about to be scheduled already in `pendingSchedule`;
  3. `.schedule` for each future target ring of the active morning (deadline and guards first, then its other latched rings) and every awake check missing from the system and not pending, each group by date;
  4. `.cancel` for every system alarm not in target, not adopted and not pending, except the alarms step 6 cancels;
  5. `.schedule` for the missing rings of the nearest morning that has not started, by date;
  6. `.cancel` for the old alarms that step 5 replaces: those of a morning other than the active one that fire after `now` and no later than the nearest morning's last ring. A kill in the middle of an evening time change then leaves tomorrow with its old rings, its new rings, or both, never neither;
  7. `.schedule` for every other missing ring (later mornings, nudges), by date. Cancelling later mornings before scheduling keeps the table near the budget (A7) when a time change replaces every id of three mornings.

R3. Past rings (date at or before `now`) are never scheduled.

R4. `pendingSchedule` lives only as long as the process that issued the schedules: building a `MorningEngine` empties it, since nothing is in flight in a new process (a reply lost to a kill would otherwise leave an id that is never cancelled). `scheduled(id, ok: true)` removes the id from `pendingSchedule`. With `ok: false` it also adds the id to `failedSchedule`, which `hasScheduleError` reports. The next pass retries it, and the engine asks for that pass itself (R1, at most once a minute), so a foreground app on Bedside overnight still retries. A later success clears the error. A due latched ring of the active morning that is still in `failedSchedule` while the app is active never reached AlarmKit, so the app plays it: it joins `session.takenOver` (sounding until tapped or backgrounded, S4) and leaves `failedSchedule`.

R5. A process killed after any effect of a pass leaves the persisted state such that the next pass completes the schedule. It never cancels a latched ring of an unfinished morning.

R6. A pass with nothing to do emits nothing. Two passes in a row with no event between them give an empty second pass.

R7. Every event that changes `EngineState` returns `.persist` as its first effect, before any AlarmKit effect.

## 13. Math session (M)

M1. A session has `ChallengeKind.math.goal(level:)` problems: 1 at levels 1 and 2, 2 at level 3. At level 3 every problem is a multiplication, and `summary(level: 3)` must say so.

M2. `enter(text)` stores the text. Once its length reaches the number of characters in the correct answer, it is checked automatically. Shorter input returns `.pending`.

M3. A wrong answer returns `.wrong`, increments `misses` (every miss, not only the first), clears the answer, and makes a new problem at the same level. `solvedCount` is kept.

M4. A right answer increments `solvedCount`, clears the answer, and returns `.correct`, or `.done` when `solvedCount == goal`.

M5. `.done` is returned exactly once. Every later `enter` or `submit` returns `.ignored` and changes nothing.

M6. `headline` is "Problem n of goal" when goal > 1, and "Solve to stop" otherwise.

## 14. Sim and processes (P)

P1. `MorningSim` delivers an alert intent to a killed process as `launched` then `alertAction`, and to a suspended process as `becameActive` then `alertAction`. The relative order is set by `IntentOrder`; rule B3 makes the outcome the same for every order.

P2. Fault injection: `killAfterEffect(n)` kills the process after its nth effect; `scheduleLatency(n)` and `cancelLatency(n)` run n other steps while a schedule or cancel is in flight; `scheduleFails(ids)` makes those schedules fail; `inFlightSurvivesKill` keeps the call the driver was awaiting when the process dies (it already reached the system) and lands it right after the next process's first table read, whose result is then stale. Scheduling an id AlarmKit already holds replaces the alarm in the fake (assumed, not verified on a device).

## 15. Invariants (checked after every simulated step)

INV1. If the process is in the foreground and a morning is active with a due latched ring, the screen is `.ringing` or `.challenge` for that morning, or `.none` only while `dismissedThisVisit` is that latest due ring. It is never `.released` of another morning, and never a challenge of another morning.

INV2. Every future latched ring of every morning seen under way that is not finished and not past its end (the latest end observed) is in the fake AlarmKit table, in flight, or in `failedSchedule`. The checker remembers these mornings and their rings itself, so a morning the engine drops from target is still checked.

INV3. A latched ring the target held while its morning was under way leaves neither the system table nor target, while the morning is not finished, except by firing (its date passing). Rings that target never held for that morning (stale leftovers) may be cancelled.

INV4. `finished[m] = .solved` happens only through C6: a challenge at a level at least the latest due ring's level, with the snapshotted kind (or math by C4).

INV5. After `solved`, once reconcile settles, the system table holds exactly that morning's unconfirmed, unexpired awake checks (checks on) or nothing for that morning (checks off).

INV6. A `finished` entry is never changed or removed, and a record never goes from solved or skipped to missed.

INV7. Running `Reconciler.plan` again right after a pass has landed returns an empty plan.

INV8. Once a pass has finished, the system table holds no id that is missing from target.

INV9. When the screen leaves `.none` while a sheet is open, `.dismissHomeSheets` was emitted in the same step. `.silence` is never emitted while the cover is hidden.

INV10. The number of skips left is never below 0, and a third skip in one Gregorian month (K2) is refused.

INV11. A morning becomes `missed` only after its last latched ring plus grace (the later of target's and the latest end observed), and `skipped` only from a `skip` event for one of its rings, or its open challenge, while a skip is left (K1).

INV12. Target never holds more than 250 future rings (A7). The nearest unfinished morning that has not started holds all `guardCount` guards, and the active morning, when target holds its deadline, holds at least `guardCount` (D2).

INV13. At each quiescent foreground step where the engine handled an event at that time, the in-app chime is playing exactly for `.ringing(sounding: true)` (F1), and the idle timer is disabled exactly as F7 says.
