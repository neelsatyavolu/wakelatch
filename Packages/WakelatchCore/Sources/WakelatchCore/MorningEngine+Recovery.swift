import Foundation

/// Recovery from partial failures: schedules AlarmKit refused (R4), guards a budget trim left out (A7),
/// and a one-off turn-off the app has not saved yet (A4).
extension MorningEngine {
    /// While a schedule has failed, the table is read again at most this often, so a failure that persists
    /// (authorization revoked) cannot spin (R4).
    public static let scheduleRetryInterval: TimeInterval = 60
    /// F4: how long an open challenge without input keeps silencing new rings.
    public static let challengeIdleLimit: TimeInterval = 30

    /// The longest a morning can last from its Ideal: the longest window, the guard window and grace.
    var maxMorningSpan: TimeInterval {
        TimeInterval(MorningPlan.maxWindowMinutes * 60) + settings.timing.guardWindow + settings.timing.grace
    }

    /// R4: a failed schedule asks for the table again, once `scheduleRetryInterval` has passed since the
    /// last request, so the next pass really comes while the app stays in the foreground.
    func retryDue(now: Date) -> Bool {
        guard !state.failedSchedule.isEmpty else { return false }
        guard let last = session.lastReadRequest else { return true }
        return now.timeIntervalSince(last) >= Self.scheduleRetryInterval
    }

    /// R1: the first tick after this process's first pass reads the table once more. A call a killed process
    /// had already sent (a cancel of a ring this process wants again) can land just after the first read.
    mutating func confirmReadDue(_ event: Event) -> Bool {
        guard case .tick = event, session.passes > 0, !session.confirmReadSent else { return false }
        session.confirmReadSent = true
        return true
    }

    /// R4: a due latched ring of the active morning whose schedule failed never reached AlarmKit, so the app
    /// plays it: it joins `takenOver` (sounding until tapped) and leaves `failedSchedule` (past rings are never
    /// retried, R3). Only in the foreground, where the app can sound.
    mutating func soundFailedRings(now: Date, active: Date?) {
        guard session.appActive, let active, !state.failedSchedule.isEmpty else { return }
        let due = state.target.filter {
            $0.morning == active && $0.latched && $0.date <= now && state.failedSchedule.contains($0.id)
        }
        for ring in due {
            session.takenOver.insert(ring.id)
            state.failedSchedule.remove(ring.id)
        }
    }

    /// A7, D2: a morning under way holds every guard. Guards a budget trim left out (the morning was armed
    /// as a far morning and no refresh ran before it started) are rebuilt from its deadline ring, with the
    /// same deterministic ids `MorningPlan.build` gives them.
    func toppedUp(_ rings: [Ring], started: Set<Date>) -> [Ring] {
        let timing = settings.timing
        guard timing.guardCount > 0 else { return rings }
        var added: [Ring] = []
        for morning in started {
            guard let deadline = rings.first(where: { $0.morning == morning && $0.kind == .deadline }) else { continue }
            let have = Set(rings.filter { $0.morning == morning && $0.kind == .guardRing }.map(\.id))
            added += (1...timing.guardCount).map {
                Ring(date: deadline.date.addingTimeInterval(Double($0) * timing.guardSpacing), kind: .guardRing,
                     level: deadline.level, morning: morning, challenge: deadline.challenge)
            }.filter { !have.contains($0.id) }
        }
        return rings + added
    }

    /// The active morning is missing guards a top-up would restore, so housekeeping refreshes target.
    func activeNeedsGuards(now: Date) -> Bool {
        guard let active = activeMorning(at: now) else { return false }
        return toppedUp(state.target, started: [active]).count != state.target.count
    }

    /// A4: settings from the app while a one-off turn-off is not saved yet. `enabled == false` means the app
    /// saved the turn-off; until then a copy saying enabled is stale, the alarm stays off and `.disableAlarm`
    /// is sent again.
    mutating func applySettings(_ newSettings: EngineSettings, out: inout EffectBuffer) {
        if !newSettings.enabled { state.turnedOff = nil }
        settings = Self.effective(newSettings, state: state)
        if state.turnedOff != nil { out.disableAlarm = true }
    }

    /// The settings the engine works with: off while a one-off turn-off is pending (A4).
    static func effective(_ settings: EngineSettings, state: EngineState) -> EngineSettings {
        var settings = settings
        if state.turnedOff != nil { settings.enabled = false }
        return settings
    }
}
