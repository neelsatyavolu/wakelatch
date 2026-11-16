import Foundation

/// The first ring and last latched ring of one morning in target.
struct MorningSpan: Hashable, Sendable {
    var first: Date
    var lastLatched: Date

    func endsBy(grace: TimeInterval) -> Date { lastLatched.addingTimeInterval(grace) }
}

/// Pure reads of engine state, for views and tests. None of them change anything.
extension MorningEngine {
    /// Spans of every morning in target. Awake checks never count (L1).
    func morningSpans() -> [Date: MorningSpan] {
        var first: [Date: Date] = [:]
        var last: [Date: Date] = [:]
        var lastLatched: [Date: Date] = [:]
        for ring in state.target where ring.kind != .awakeCheck {
            first[ring.morning] = min(first[ring.morning] ?? ring.date, ring.date)
            last[ring.morning] = max(last[ring.morning] ?? ring.date, ring.date)
            if ring.latched { lastLatched[ring.morning] = max(lastLatched[ring.morning] ?? ring.date, ring.date) }
        }
        return first.reduce(into: [:]) { spans, entry in
            let end = lastLatched[entry.key] ?? last[entry.key] ?? entry.value
            // The Ideal counts as a start: a morning adopted with only its future rings has still begun (L1).
            spans[entry.key] = MorningSpan(first: min(entry.value, entry.key), lastLatched: end)
        }
    }

    /// The oldest morning that has started (its first ring, a nudge counts, or its Ideal is at or before
    /// `now`), is not in `finished`, and whose last latched ring plus grace is not yet past.
    /// Awake checks never make a morning active.
    public func activeMorning(at now: Date) -> Date? {
        let grace = settings.timing.grace
        return morningSpans()
            .filter { state.finished[$0.key] == nil && $0.value.first <= now && now <= $0.value.endsBy(grace: grace) }
            .keys.min()
    }

    /// The active morning with its deadline and end, for "under way" UI (D3).
    public func underWay(at now: Date) -> UnderWay? {
        guard let morning = activeMorning(at: now), let span = morningSpans()[morning] else { return nil }
        return UnderWay(morning: morning, deadline: deadline(of: morning),
                        endsBy: span.endsBy(grace: settings.timing.grace))
    }

    /// The due latched ring of `morning` that sets the bar: the highest level, then the latest date, at or
    /// before `now`. Levels never fall with date in a planned morning, so this is the latest due ring; a stray
    /// lower-level ring dated later can never lower the bar or bring back Snooze past the Deadline.
    public func latestDueLatched(of morning: Date, at now: Date) -> Ring? {
        state.target.filter { $0.morning == morning && $0.latched && $0.date <= now }
            .max { ($0.level, $0.date) < ($1.level, $1.date) }
    }

    /// The first latched ring of the same morning after `now`: the "Snoozed until" time.
    public func nextLatched(of morning: Date, after now: Date) -> Ring? {
        state.target.filter { $0.morning == morning && $0.latched && $0.date > now }.min { $0.date < $1.date }
    }

    /// The challenge a ring requires: its snapshotted kind (math after `challengeUnavailable`) at its level.
    public func requiredChallenge(for ring: Ring) -> ActiveChallenge {
        let kind = ring.challenge ?? .math
        if let open = state.challenge, open.morning == ring.morning, open.kind == .math,
           open.ring.challenge == ring.challenge {
            return ActiveChallenge(ring: ring, kind: .math)
        }
        return ActiveChallenge(ring: ring, kind: kind)
    }

    /// "Ring 3 of 10" for a latched ring, and its morning's deadline.
    public func position(of ring: Ring) -> RingPosition {
        let latched = state.target.filter { $0.morning == ring.morning && $0.latched }
        let number = (latched.firstIndex { $0.id == ring.id } ?? 0) + 1
        return RingPosition(number: number, total: latched.count,
                            deadline: latched.first { $0.kind == .deadline }?.date)
    }

    /// The next morning that will ring (Ideal), skipping the active one. Nil when the alarm is off.
    public func nextMorning(at now: Date) -> Date? {
        guard settings.enabled else { return nil }
        let active = activeMorning(at: now)
        return morningSpans()
            .filter { $0.key != active && state.finished[$0.key] == nil && $0.value.first > now }
            .keys.min()
    }

    /// The rings of a morning in target (awake checks included), oldest first.
    public func rings(of morning: Date) -> [Ring] {
        state.target.filter { $0.morning == morning }
    }

    /// First ring date of each awake-check group not yet confirmed or expired.
    public func pendingAwakeChecks(at now: Date) -> [Date] {
        let expiry = settings.timing.awakeCheckExpiry
        let live = state.target.filter {
            $0.kind == .awakeCheck && !state.acknowledged.contains($0.id) && now.timeIntervalSince($0.date) <= expiry
        }
        let firsts = Dictionary(grouping: live) { GroupKey(morning: $0.morning, group: $0.checkGroup ?? 0) }
            .compactMap { $0.value.map(\.date).min() }
        return firsts.sorted()
    }

    /// Emergency skips left in `now`'s calendar month.
    public func skipsLeft(at now: Date) -> Int {
        state.skips.remaining(at: now, calendar: calendar)
    }

    /// True when the last attempt to schedule some ring failed.
    public var hasScheduleError: Bool { !state.failedSchedule.isEmpty }

    /// Screen is ringing, challenge or awake check; or Released within `releasedKeepAwake` of the solve;
    /// or Bedside with keep-screen-on while charging.
    public func idleTimerDisabled(at now: Date) -> Bool {
        let bedside = session.bedside && settings.keepScreenOn && session.charging
        switch session.screen {
        case .ringing, .challenge, .awakeCheck:
            return true
        case .released:
            let fresh = session.released.map { now.timeIntervalSince($0.since) < settings.timing.releasedKeepAwake }
            return fresh == true || bedside
        case .none:
            return bedside
        }
    }

    /// The morning's deadline from its deadline ring, or from the current window when that ring is gone.
    func deadline(of morning: Date) -> Date {
        state.target.first { $0.morning == morning && $0.kind == .deadline }?.date
            ?? morning.addingTimeInterval(MorningPlan.window(times: settings.times, timing: settings.timing))
    }
}

private struct GroupKey: Hashable {
    let morning: Date
    let group: Int
}
