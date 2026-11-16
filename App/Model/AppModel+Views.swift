import Foundation
import WakelatchCore

/// What views read, and the buttons they press. Every button becomes one engine event.
extension AppModel {
    // MARK: reads

    /// The morning screen to show. `.none` is home (or Bedside).
    var screen: Screen { demo?.screen ?? engine.screen }

    /// Bedside mode is on. Setting it sends `.bedsideChanged`.
    var bedside: Bool {
        get { demo?.bedside ?? engine.session.bedside }
        set { send(.bedsideChanged(newValue, now: now)) }
    }

    var calendar: Calendar { engine.calendar }

    /// A morning that has started and is not finished: home says it is under way (D3).
    var underWay: UnderWay? { engine.underWay(at: now) }

    /// The next morning that will ring, and its rings. Nil when the alarm is off.
    var nextMorning: (day: Date, rings: [Ring])? {
        guard timesProblem == nil, let morning = engine.nextMorning(at: now) else { return nil }
        return (morning, engine.rings(of: morning))
    }

    /// Validation message for the chosen times, or nil when they work.
    var timesProblem: String? {
        settings.times.windowMinutes > MorningPlan.maxWindowMinutes
            ? "Deadline must be within 3 hours of Ideal." : nil
    }

    var scheduleError: String? {
        engine.hasScheduleError ? "Couldn't schedule every alarm. Wakelatch tries again every minute." : nil
    }

    var syncing: Bool { alarmCallsInFlight > 0 }

    /// Rings of the next morning that AlarmKit really holds (nil before the first table read).
    var confirmedNextRings: Int? {
        guard let table = systemTable, let next = nextMorning else { return nil }
        let held = Set(table.map(\.id))
        return next.rings.filter { held.contains($0.id) }.count
    }

    /// The latched rings of a morning, in order.
    func latchedRings(of morning: Date) -> [Ring] {
        (demo?.rings ?? engine.state.target).filter { $0.morning == morning && $0.latched }
    }

    /// "Ring 3 of 10" numbers and the deadline for a ring's morning.
    func position(of ring: Ring) -> RingPosition {
        guard demo != nil else { return engine.position(of: ring) }
        let latched = latchedRings(of: ring.morning)
        return RingPosition(number: (latched.firstIndex { $0.id == ring.id } ?? 0) + 1, total: latched.count,
                            deadline: latched.first { $0.kind == .deadline }?.date)
    }

    var skipsLeft: Int { engine.skipsLeft(at: now) }

    /// First ring time of each awake check still to come.
    var pendingAwakeChecks: [Date] { engine.pendingAwakeChecks(at: now) }

    /// "Up by Ideal on 3 of the last 5 mornings." Nil until there's a morning to count.
    var historyLine: String? {
        let recent = engine.state.records.filter { !$0.skipped }.suffix(7)
        guard !recent.isEmpty else { return nil }
        let up = recent.filter(\.upByIdeal).count
        return "Up by Ideal on \(up) of the last \(recent.count) mornings."
    }

    /// Screenshot mode: the time the morning screens show.
    var demoNow: Date? { demo?.now }

    /// JSON for the hidden `debug.state` element. Nil unless a UI-test flag is set.
    var debugJSON: String? {
        guard environment.options.debug else { return nil }
        return DebugState(screen: screen, state: engine.state, table: systemTable, intents: intentsReceived,
                          skipsLeft: skipsLeft, sound: playing).json
    }

    // MARK: buttons

    func snooze(_ ring: Ring) { send(.tapSnooze(ring.id, now: now)) }

    func dismissNudge(_ ring: Ring) { send(.tapNudgeStop(ring.id, now: now)) }

    func startChallenge(_ ring: Ring) { send(.tapStartChallenge(ring.id, now: now)) }

    /// The open challenge's ring was solved. The engine checks level, kind and morning (C6).
    func solved(_ ring: Ring) { send(.solved(ringID: ring.id, now: now)) }

    /// Emergency skip. Returns false when it was refused (none left this month, or the morning is over).
    func skip(_ ring: Ring) -> Bool {
        send(.skip(ringID: ring.id, now: now))
        return engine.state.finished[ring.morning] == .skipped
    }

    func confirmAwake(_ ring: Ring) { send(.tapImUp(ringID: ring.id, now: now)) }

    func closeReleased() { send(.closeReleased(now: now)) }

    /// The sleeper typed, walked, shook or looked at the camera. Keeps the open challenge in use, so it
    /// silences rings that come while it is open (F4). Sent at most every 5 s, unless an alarm is ringing.
    func challengeActivity() {
        let now = now
        let ringing = lastAlerting?.isEmpty == false
        if let last = lastActivitySent, now.timeIntervalSince(last) < 5, !ringing { return }
        lastActivitySent = now
        send(.challengeActivity(now: now))
    }

    /// The sensor for `kind` is denied or missing: the open challenge falls back to math (C4).
    func challengeUnavailable(_ kind: ChallengeKind) { send(.challengeUnavailable(kind, now: now)) }
}
