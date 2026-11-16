import Foundation

/// The morning state machine. `handle(_:)` is the only writer of morning state; it is synchronous and
/// pure: time, calendar, settings, audibility and cover visibility all arrive as inputs.
/// The rules it implements are in docs/morning-contract.md.
public struct MorningEngine: Sendable {
    public internal(set) var state: EngineState
    public internal(set) var session: SessionState
    public internal(set) var settings: EngineSettings
    public internal(set) var calendar: Calendar

    /// A new engine is a new process: nothing it hands to AlarmKit is in flight yet, so persisted
    /// `pendingSchedule` entries are stale and dropped (R4). A background intent can start a process that
    /// never receives `launched`, so this cannot wait for that event.
    /// Settings saying `enabled == false` mean the app saved a pending one-off turn-off (A4).
    public init(state: EngineState, settings: EngineSettings, calendar: Calendar) {
        var state = state
        state.pendingSchedule = []
        if !settings.enabled { state.turnedOff = nil }
        self.state = state
        self.session = SessionState()
        self.settings = Self.effective(settings, state: state)
        self.calendar = calendar
    }

    /// The screen after the last event.
    public var screen: Screen { session.screen }

    /// Applies one event and returns the effects to run, in order. `.persist` comes first whenever
    /// `state` changed.
    public mutating func handle(_ event: Event) -> [Effect] {
        let before = state
        let screenBefore = session.screen
        let now = event.now
        var out = EffectBuffer()
        housekeep(now: now, out: &out)
        apply(event, now: now, out: &out)
        settle(now: now, out: &out)
        if screenBefore == .none && session.screen != .none { out.dismissHomeSheets = true }
        if !session.tableRequested && state.turnedOff != nil { out.disableAlarm = true }
        if case .systemTable = event {} else if before.target != state.target || !session.tableRequested
            || retryDue(now: now) || confirmReadDue(event) {
            out.readSystemTable = true
        }
        if out.readSystemTable { session.lastReadRequest = now }
        session.tableRequested = true
        return out.effects(persist: before != state)
    }

    private mutating func apply(_ event: Event, now: Date, out: inout EffectBuffer) {
        switch event {
        case .launched, .becameActive, .enteredBackground, .tick:
            applyLifecycle(event, now: now, out: &out)
        case let .alerting(ids, _, audible, coverVisible):
            // In the background nobody sees the screen, and a suspended app misses the update that the alert
            // stopped, so a ring seen there must not stay on screen (S5) when the app opens. Opening reads
            // the table again (F8).
            session.alerting = session.appActive ? ids : []
            session.audible = audible
            session.coverVisible = coverVisible
        case let .coverShown(_, audible):
            session.coverVisible = true
            session.audible = audible
        case let .alertAction(ringID, action, _):
            alertAction(ringID, action, now: now, out: &out)
        case let .systemTable(alarms, _):
            reconcile(alarms, now: now, out: &out)
        case let .scheduled(id, ok, _):
            scheduled(id, ok: ok, out: &out)
        case .tapSnooze, .tapNudgeStop, .tapStartChallenge, .solved, .skip, .tapImUp, .closeReleased,
             .challengeUnavailable, .challengeActivity:
            applyInApp(event, now: now, out: &out)
        case let .bedsideChanged(on, _):
            if on && !session.bedside { out.dismissHomeSheets = true }
            session.bedside = on
        case let .chargingChanged(on, _):
            session.charging = on
        case let .settingsChanged(newSettings, _):
            applySettings(newSettings, out: &out)
            refreshTarget(now: now)
        case let .calendarChanged(newCalendar, _):
            calendar = newCalendar
            refreshTarget(now: now)
        }
    }

    private mutating func applyLifecycle(_ event: Event, now: Date, out: inout EffectBuffer) {
        switch event {
        case .launched:
            // A fresh visit, but the sound and idle timer already sent by this process (an intent can arrive
            // before `launched`) stay known, so the next change is still emitted (F1, F7).
            session = SessionState(appActive: true, idleTimerDisabled: session.idleTimerDisabled,
                                   sound: session.sound, tableRequested: session.tableRequested,
                                   lastReadRequest: session.lastReadRequest, passes: session.passes,
                                   confirmReadSent: session.confirmReadSent)
            refreshTarget(now: now)
            out.readSystemTable = true
        case .becameActive:
            session.appActive = true
            refreshTarget(now: now)
            out.readSystemTable = true
        case .enteredBackground:
            session.appActive = false
            session.dismissedThisVisit = nil
            session.nudge = nil
            session.released = nil
            session.alerting = []
            session.takenOver = []
            session.coverVisible = false
            session.challengeActivity = nil
        default:
            break
        }
    }
}
