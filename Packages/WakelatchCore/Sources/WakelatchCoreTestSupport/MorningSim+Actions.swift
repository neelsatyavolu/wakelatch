import Foundation
import WakelatchCore

/// In-app buttons, configuration changes and table set-up. Each returns the effects of its own event
/// (not of the follow-up events it caused); nothing happens while the process is killed.
extension MorningSim {
    /// Sends one event to the engine (launching nothing) and runs its effects.
    @discardableResult
    public mutating func send(_ event: Event) -> [Effect] {
        deliver(event)
    }

    @discardableResult
    public mutating func tapSnooze(_ ringID: UUID) -> [Effect] {
        deliver(.tapSnooze(ringID, now: now))
    }

    @discardableResult
    public mutating func tapNudgeStop(_ ringID: UUID) -> [Effect] {
        deliver(.tapNudgeStop(ringID, now: now))
    }

    @discardableResult
    public mutating func tapStartChallenge(_ ringID: UUID) -> [Effect] {
        deliver(.tapStartChallenge(ringID, now: now))
    }

    /// The challenge view reports a solve for `ringID`.
    @discardableResult
    public mutating func solve(_ ringID: UUID) -> [Effect] {
        deliver(.solved(ringID: ringID, now: now))
    }

    /// Solves whatever challenge the screen shows. Returns nil when no challenge is open.
    @discardableResult
    public mutating func solveOpenChallenge() -> [Effect]? {
        guard let open = openChallenge else { return nil }
        return solve(open.ring.id)
    }

    @discardableResult
    public mutating func skip(_ ringID: UUID) -> [Effect] {
        deliver(.skip(ringID: ringID, now: now))
    }

    @discardableResult
    public mutating func tapImUp(_ ringID: UUID) -> [Effect] {
        deliver(.tapImUp(ringID: ringID, now: now))
    }

    @discardableResult
    public mutating func closeReleased() -> [Effect] {
        deliver(.closeReleased(now: now))
    }

    @discardableResult
    public mutating func challengeUnavailable(_ kind: ChallengeKind) -> [Effect] {
        deliver(.challengeUnavailable(kind, now: now))
    }

    /// Changes the user's settings. A running engine gets `settingsChanged`; a killed one sees them on launch.
    @discardableResult
    public mutating func changeSettings(_ change: (inout EngineSettings) -> Void) -> [Effect] {
        change(&settings)
        return deliver(.settingsChanged(settings, now: now))
    }

    /// Changes the time zone or calendar. A running engine gets `calendarChanged`.
    @discardableResult
    public mutating func changeCalendar(_ newCalendar: Calendar) -> [Effect] {
        calendar = newCalendar
        return deliver(.calendarChanged(newCalendar, now: now))
    }

    /// Puts an alarm in the fake table behind the app's back (a leftover from an earlier run or build).
    public mutating func plant(_ ring: Ring, alerting: Bool = false) {
        system.insert(ring, alerting: alerting)
    }

    /// Puts an alarm without Wakelatch metadata in the fake table.
    public mutating func plantForeign(id: UUID, fireDate: Date) {
        system.insertForeign(id: id, fireDate: fireDate)
    }
}
