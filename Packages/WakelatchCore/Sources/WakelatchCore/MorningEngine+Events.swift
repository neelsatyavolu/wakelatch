import Foundation

/// Alert buttons (B), reconcile results (R) and in-app actions (C, K, W).
extension MorningEngine {
    mutating func alertAction(_ ringID: UUID, _ action: AlertAction, now: Date, out: inout EffectBuffer) {
        switch action {
        case .none: break
        case .openToChallenge: state.route = PendingRoute(ringID: ringID, at: now)
        case .confirmAwake: confirmGroup(of: ringID, out: &out)
        }
    }

    /// R1-R4: one reconcile pass against AlarmKit's table. Ids about to be scheduled go into
    /// `pendingSchedule` before the `.persist` that precedes them.
    /// On the first pass a state ever runs (new install, or state lost or reset mid-morning), with no active
    /// morning in target, the morning under way that AlarmKit still holds is adopted instead of cancelled.
    mutating func reconcile(_ alarms: [SystemAlarm], now: Date, out: inout EffectBuffer) {
        // Alerting is only tracked while active (F8): opening the app reads the table again.
        session.alerting = session.appActive
            ? Set(alarms.filter(\.alerting).map(\.id)).subtracting(session.takenOver) : []
        session.passes += 1
        let timing = settings.timing
        let orphan = state.firstPass == nil
            ? Reconciler.orphanMorning(in: alarms, target: state.target, finished: state.finished, now: now,
                                       lead: timing.nudgeOffsets.max() ?? 0, grace: timing.grace,
                                       maxSpan: maxMorningSpan)
            : nil
        if state.firstPass == nil { state.firstPass = now }
        let active = activeMorning(at: now) ?? orphan
        let plan = Reconciler.plan(target: state.target, system: alarms, pending: state.pendingSchedule,
                                   activeMorning: active, now: now)
        if !plan.adopt.isEmpty { state.target = Self.sorted(state.target + plan.adopt) }
        let missed = waitingAlarmsOfMissedMornings(alarms)
        plan.firstSchedules.forEach { schedule($0, out: &out) }
        plan.firstCancels.filter { !missed.contains($0) }.forEach { out.cancel($0) }
        plan.nextSchedules.forEach { schedule($0, stage: .next, out: &out) }
        plan.lateCancels.filter { !missed.contains($0) }.forEach { out.cancelLate($0) }
        plan.lateSchedules.forEach { schedule($0, stage: .late, out: &out) }
        let systemIDs = Set(alarms.map(\.id))
        let future = Set(state.target.filter { $0.date > now }.map(\.id))
        state.failedSchedule = state.failedSchedule.filter { future.contains($0) && !systemIDs.contains($0) }
    }

    /// R4. A ring that left target while its schedule was in flight is cancelled once it lands.
    mutating func scheduled(_ id: UUID, ok: Bool, out: inout EffectBuffer) {
        state.pendingSchedule.remove(id)
        let inTarget = state.target.contains { $0.id == id }
        if ok {
            state.failedSchedule.remove(id)
            if !inTarget { out.cancel(id) }
        } else if inTarget {
            state.failedSchedule.insert(id)
        }
    }

    mutating func schedule(_ ring: Ring, stage: EffectBuffer.Stage = .first, out: inout EffectBuffer) {
        state.pendingSchedule.insert(ring.id)
        out.schedule(ring, stage: stage)
    }

    /// L3: alarms of a morning that ended as missed and that have not rung yet. On an honest clock there are
    /// none: a morning is missed only after its last ring and grace. They exist when the device clock was
    /// moved forward, and are left in AlarmKit so setting the clock back cannot cancel the morning for good.
    private func waitingAlarmsOfMissedMornings(_ alarms: [SystemAlarm]) -> Set<UUID> {
        Set(alarms.filter { alarm in
            !alarm.alerting && alarm.ring.map { state.finished[$0.morning] == .missed } == true
        }.map(\.id))
    }

    mutating func applyInApp(_ event: Event, now: Date, out: inout EffectBuffer) {
        switch event {
        case let .tapSnooze(id, _): tapSnooze(id, now: now, out: &out)
        case let .tapNudgeStop(id, _): tapNudgeStop(id, now: now, out: &out)
        case let .tapStartChallenge(id, _): tapStartChallenge(id, now: now, out: &out)
        case let .solved(id, _): solved(id, now: now, out: &out)
        case let .skip(id, _): skip(id, now: now, out: &out)
        case let .tapImUp(id, _):
            session.coverVisible = true
            confirmGroup(of: id, out: &out)
        case .closeReleased: session.released = nil
        case let .challengeUnavailable(kind, _): challengeUnavailable(kind)
        case .challengeActivity:
            session.coverVisible = true
            session.challengeActivity = now
        default: break
        }
    }

    /// C8/C9: snooze the latest due snoozable ring; refused on the deadline and guards.
    private mutating func tapSnooze(_ id: UUID, now: Date, out: inout EffectBuffer) {
        guard let active = activeMorning(at: now), let due = latestDueLatched(of: active, at: now),
              due.allowsSnooze else { return }
        session.coverVisible = true
        state.acknowledged.insert(due.id)
        session.dismissedThisVisit = due.id
        silenceTapped(id, now: now, out: &out)
        silenceMorning(active, out: &out)
    }

    private mutating func tapNudgeStop(_ id: UUID, now: Date, out: inout EffectBuffer) {
        session.coverVisible = true
        if state.target.contains(where: { $0.id == id && $0.kind == .nudge }) { state.acknowledged.insert(id) }
        if session.nudge?.ringID == id { session.nudge = nil }
        silenceTapped(id, now: now, out: &out)
    }

    /// C1/C2: the challenge opens for the latest due ring, whichever ring was tapped.
    private mutating func tapStartChallenge(_ id: UUID, now: Date, out: inout EffectBuffer) {
        session.coverVisible = true
        silenceTapped(id, now: now, out: &out)
        guard let active = activeMorning(at: now), let due = latestDueLatched(of: active, at: now) else { return }
        silenceMorning(active, out: &out)
        state.challenge = openChallenge(for: due)
        session.challengeActivity = now
    }

    /// F2: an in-app button always silences its ring, at any volume. A ring that is not due yet cannot be
    /// sounding, so it is never silenced (that would stop a scheduled alarm).
    private mutating func silenceTapped(_ id: UUID, now: Date, out: inout EffectBuffer) {
        if !state.target.contains(where: { $0.id == id && $0.date > now }) { out.silence(id) }
        session.alerting.remove(id)
        session.takenOver.remove(id)
    }

    /// Stops everything of the morning that is alerting or held in-app.
    private mutating func silenceMorning(_ morning: Date, out: inout EffectBuffer) {
        for ring in state.target where ring.morning == morning && ring.kind != .awakeCheck {
            if session.alerting.contains(ring.id) { out.silence(ring.id) }
            session.alerting.remove(ring.id)
            session.takenOver.remove(ring.id)
        }
    }

    /// C6/C7: accepted only for the open challenge, on the active morning, at the due ring's level and kind.
    private mutating func solved(_ id: UUID, now: Date, out: inout EffectBuffer) {
        guard let open = state.challenge, open.ring.id == id else { return }
        let morning = open.morning
        guard activeMorning(at: now) == morning, state.finished[morning] == nil,
              let due = latestDueLatched(of: morning, at: now), open.level >= due.level,
              kindMatches(open, due) else { return }
        finish(morning, .solved, upAt: now, now: now, out: &out)
        if settings.awakeChecks {
            let checks = MorningPlan.awakeChecks(morning: morning, solvedAt: now, timing: settings.timing)
            state.target = Self.sorted(state.target + checks)
            checks.filter { $0.date > now }.forEach { schedule($0, out: &out) }
        }
        state.route = nil
        session.dismissedThisVisit = nil
        if let record = state.records.last(where: { $0.morning == morning }) {
            session.released = ReleasedOnScreen(record: record, since: now)
        }
    }

    private func kindMatches(_ open: ActiveChallenge, _ due: Ring) -> Bool {
        let snapshot = due.challenge ?? .math
        return open.kind == snapshot || (open.kind == .math && open.ring.challenge == due.challenge)
    }

    /// K1/K2: ends the active morning when a skip is left this month.
    private mutating func skip(_ id: UUID, now: Date, out: inout EffectBuffer) {
        let ring = state.target.first { $0.id == id } ?? state.challenge.map(\.ring).flatMap { $0.id == id ? $0 : nil }
        guard let ring, let active = activeMorning(at: now), ring.morning == active, state.finished[active] == nil,
              state.skips.use(at: now, calendar: calendar) else { return }
        finish(active, .skipped, upAt: nil, now: now, out: &out)
        state.route = nil
        session.released = nil
        session.dismissedThisVisit = nil
        session.nudge = nil
    }

    /// W3: confirms every ring of the awake-check group `ringID` belongs to.
    private mutating func confirmGroup(of ringID: UUID, out: inout EffectBuffer) {
        guard let ring = state.target.first(where: { $0.id == ringID && $0.kind == .awakeCheck }) else { return }
        let group = state.target.filter {
            $0.kind == .awakeCheck && $0.morning == ring.morning && $0.checkGroup == ring.checkGroup
        }
        let ids = Set(group.map(\.id))
        state.acknowledged.formUnion(ids)
        state.target.removeAll { ids.contains($0.id) }
        group.forEach { out.cancel($0.id) }
        session.alerting.subtract(ids)
        session.takenOver.subtract(ids)
    }

    /// C4: the open challenge falls back to math at the same ring and level.
    private mutating func challengeUnavailable(_ kind: ChallengeKind) {
        guard let open = state.challenge, open.kind == kind, kind != .math else { return }
        state.challenge = ActiveChallenge(ring: open.ring, kind: .math)
    }
}
