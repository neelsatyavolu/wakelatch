import Foundation

/// The effects one event produces, collected while the engine works and emitted in contract order:
/// persist, disable, dismiss sheets, schedules, cancels, the nearest morning's schedules, the cancels of the
/// alarms they replace, late schedules, silences, sound, idle timer, read table.
/// `.disableAlarm` comes straight after `.persist` so it never waits behind AlarmKit calls (A4).
struct EffectBuffer {
    var dismissHomeSheets = false
    /// When a schedule goes out in a reconcile pass (R2).
    enum Stage {
        /// The active morning and awake checks: before any cancel.
        case first
        /// The nearest morning that has not started: after the cancels of later mornings, before the
        /// cancels of the alarms it replaces.
        case next
        /// Every other morning: after all cancels.
        case late
    }

    private(set) var schedules: [Ring] = []
    private(set) var cancels: [UUID] = []
    private(set) var nextSchedules: [Ring] = []
    private(set) var lateCancels: [UUID] = []
    private(set) var lateSchedules: [Ring] = []
    private(set) var silences: [UUID] = []
    var sound: SoundCommand?
    var idleTimerDisabled: Bool?
    var disableAlarm = false
    var readSystemTable = false
    /// A morning finished: future mornings must be re-armed before the event ends.
    var needsRefresh = false

    mutating func schedule(_ ring: Ring, stage: Stage = .first) {
        guard !(schedules + nextSchedules + lateSchedules).contains(where: { $0.id == ring.id }) else { return }
        switch stage {
        case .first: schedules.append(ring)
        case .next: nextSchedules.append(ring)
        case .late: lateSchedules.append(ring)
        }
    }

    mutating func cancel(_ id: UUID) {
        if !cancels.contains(id), !lateCancels.contains(id) { cancels.append(id) }
    }

    /// A cancel that waits for the nearest morning's new rings (R2).
    mutating func cancelLate(_ id: UUID) {
        if !cancels.contains(id), !lateCancels.contains(id) { lateCancels.append(id) }
    }

    mutating func silence(_ id: UUID) {
        if !silences.contains(id) { silences.append(id) }
    }

    func effects(persist: Bool) -> [Effect] {
        var out: [Effect] = persist ? [.persist] : []
        if disableAlarm { out.append(.disableAlarm) }
        if dismissHomeSheets { out.append(.dismissHomeSheets) }
        out += schedules.map(Effect.schedule)
        out += cancels.map(Effect.cancel)
        out += nextSchedules.map(Effect.schedule)
        out += lateCancels.map(Effect.cancel)
        out += lateSchedules.map(Effect.schedule)
        out += silences.map(Effect.silence)
        if let sound { out.append(.sound(sound)) }
        if let idleTimerDisabled { out.append(.setIdleTimerDisabled(idleTimerDisabled)) }
        if readSystemTable { out.append(.readSystemTable) }
        return out
    }
}

extension Event {
    /// The time every event carries.
    public var now: Date {
        switch self {
        case let .launched(now), let .becameActive(now), let .enteredBackground(now), let .tick(now),
             let .alerting(_, now, _, _), let .coverShown(now, _), let .alertAction(_, _, now),
             let .systemTable(_, now), let .scheduled(_, _, now), let .tapSnooze(_, now),
             let .tapNudgeStop(_, now), let .tapStartChallenge(_, now), let .solved(_, now), let .skip(_, now),
             let .tapImUp(_, now), let .closeReleased(now), let .challengeUnavailable(_, now),
             let .challengeActivity(now),
             let .bedsideChanged(_, now), let .chargingChanged(_, now), let .settingsChanged(_, now),
             let .calendarChanged(_, now):
            now
        }
    }
}
