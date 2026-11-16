import Foundation

/// Screen priority (S1-S7), takeover silencing (F3-F5), sound (F1) and the idle timer (F7).
extension MorningEngine {
    /// Runs after every event: housekeeping, then the screen and everything that follows from it.
    mutating func settle(now: Date, out: inout EffectBuffer) {
        housekeep(now: now, out: &out)
        let active = activeMorning(at: now)
        soundFailedRings(now: now, active: active)
        applyRoute(now: now, active: active)
        session.screen = resolveScreen(now: now, active: active)
        // Home has no cover: the next screen waits for `coverShown` before silencing anything (F5).
        if session.screen == .none { session.coverVisible = false }
        silenceForScreen(now: now, out: &out)
        updateSound(out: &out)
        updateIdleTimer(now: now, out: &out)
    }

    /// S1: a fresh route to a latched ring of the active morning opens its challenge once the app is active.
    private mutating func applyRoute(now: Date, active: Date?) {
        guard let route = state.route else { return }
        let ring = state.target.first { $0.id == route.ringID }
        guard now.timeIntervalSince(route.at) <= settings.timing.routeMaxAge, let ring, ring.latched,
              let active, ring.morning == active, state.finished[active] == nil else {
            state.route = nil
            return
        }
        guard session.appActive else { return }
        if let due = latestDueLatched(of: active, at: now) {
            state.challenge = openChallenge(for: due)
            session.challengeActivity = now
        }
        state.route = nil
    }

    /// C1-C3: keep the open challenge of the same morning unless the due ring needs a higher level or
    /// another kind; otherwise the challenge the due ring requires.
    func openChallenge(for due: Ring) -> ActiveChallenge {
        if let open = state.challenge, open.morning == due.morning, !needsUpgrade(open, to: due) { return open }
        return requiredChallenge(for: due)
    }

    func needsUpgrade(_ open: ActiveChallenge, to due: Ring) -> Bool {
        due.level > open.level || due.challenge != open.ring.challenge
    }

    private mutating func resolveScreen(now: Date, active: Date?) -> Screen {
        if let open = state.challenge {
            if open.morning == active, let due = latestDueLatched(of: open.morning, at: now) {
                let current = openChallenge(for: due)
                state.challenge = current
                session.released = nil
                return .challenge(current)
            }
            state.challenge = nil
        }
        if let check = dueAwakeCheck(now: now) {
            session.released = nil
            return .awakeCheck(check)
        }
        if let active, let due = latestDueLatched(of: active, at: now) {
            session.released = nil
            return ringing(active, due: due, now: now)
        }
        if let nudge = nudgeOnScreen(now: now) {
            session.released = nil
            return .ringing(nudge, sounding: true, snoozedUntil: nil)
        }
        if let released = session.released { return .released(released.record) }
        return .none
    }

    /// S3: the latest due awake-check ring that is not confirmed and not expired.
    private func dueAwakeCheck(now: Date) -> Ring? {
        let expiry = settings.timing.awakeCheckExpiry
        return state.target.filter {
            $0.kind == .awakeCheck && $0.date <= now && !state.acknowledged.contains($0.id)
                && now.timeIntervalSince($0.date) <= expiry
        }.max { $0.date < $1.date }
    }

    /// S4 and S9 (D1: a snoozed ring shows "Snoozed until", never home, except right after an in-app Snooze).
    private mutating func ringing(_ morning: Date, due: Ring, now: Date) -> Screen {
        if let dismissed = session.dismissedThisVisit, dismissed != due.id { session.dismissedThisVisit = nil }
        if isSounding(morning, now: now) { return .ringing(due, sounding: true, snoozedUntil: nil) }
        if session.dismissedThisVisit == due.id { return .none }
        if due.allowsSnooze {
            return .ringing(due, sounding: false, snoozedUntil: nextLatched(of: morning, after: now)?.date)
        }
        return .ringing(due, sounding: false, snoozedUntil: nil)
    }

    /// A due latched ring of the morning is alerting, or the app took it over and it was not tapped yet.
    private func isSounding(_ morning: Date, now: Date) -> Bool {
        state.target.contains {
            $0.morning == morning && $0.latched && $0.date <= now
                && (session.alerting.contains($0.id) || session.takenOver.contains($0.id))
        }
    }

    /// S5: an alerting nudge shows, and stays after its alert stops until tapped, backgrounded or capped.
    private mutating func nudgeOnScreen(now: Date) -> Ring? {
        let alerting = state.target.filter {
            $0.kind == .nudge && session.alerting.contains($0.id) && !state.acknowledged.contains($0.id)
        }.max { $0.date < $1.date }
        if let alerting, session.nudge?.ringID != alerting.id {
            session.nudge = NudgeOnScreen(ringID: alerting.id, since: now)
        }
        guard let shown = session.nudge,
              let ring = state.target.first(where: { $0.id == shown.ringID }),
              !state.acknowledged.contains(ring.id), state.finished[ring.morning] == nil else {
            session.nudge = nil
            return nil
        }
        // Past the cap the record is kept, so a nudge still alerting does not show again.
        return now.timeIntervalSince(shown.since) < settings.timing.nudgeScreenCap ? ring : nil
    }

    /// F3/F4/F5: with the cover visible, a sounding ringing screen takes over (when audible), and an open
    /// challenge that is being worked on silences every alerting ring of its morning. A challenge left
    /// without input lets the system alarm ring until the next input. A cover in an app that is not active
    /// is not visible: iOS can keep a backgrounded app running, and its cover still appears there.
    private mutating func silenceForScreen(now: Date, out: inout EffectBuffer) {
        guard session.appActive, session.coverVisible else { return }
        switch session.screen {
        case let .ringing(ring, sounding: true, _) where session.audible:
            for id in alertingRings(of: ring.morning) {
                out.silence(id)
                session.alerting.remove(id)
                session.takenOver.insert(id)
            }
        case let .challenge(open) where challengeInUse(now: now):
            for id in alertingRings(of: open.morning) {
                out.silence(id)
                session.alerting.remove(id)
            }
        default:
            break
        }
    }

    /// F4: the challenge had input within `challengeIdleLimit`.
    private func challengeInUse(now: Date) -> Bool {
        guard let last = session.challengeActivity else { return false }
        return now.timeIntervalSince(last) <= Self.challengeIdleLimit
    }

    private func alertingRings(of morning: Date) -> [UUID] {
        state.target.filter { $0.morning == morning && $0.kind != .awakeCheck && session.alerting.contains($0.id) }
            .map(\.id)
    }

    /// F1: the chime follows the screen while the app is active, sent only on change.
    private mutating func updateSound(out: inout EffectBuffer) {
        let sound: SoundCommand
        if session.appActive, case let .ringing(ring, sounding: true, _) = session.screen {
            sound = .play(nudge: ring.kind == .nudge)
        } else {
            sound = .stop
        }
        guard sound != session.sound else { return }
        session.sound = sound
        out.sound = sound
    }

    /// F7: one writer for the idle timer, sent only on change.
    private mutating func updateIdleTimer(now: Date, out: inout EffectBuffer) {
        let disabled = idleTimerDisabled(at: now)
        guard disabled != session.idleTimerDisabled else { return }
        session.idleTimerDisabled = disabled
        out.idleTimerDisabled = disabled
    }
}
