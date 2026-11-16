import Foundation

/// One alarm as AlarmKit reports it. `ring` is rebuilt from the alarm's metadata; nil for alarms
/// without Wakelatch metadata (scheduled by an older build).
public struct SystemAlarm: Hashable, Sendable {
    public let id: UUID
    public let fireDate: Date?
    public let ring: Ring?
    public let alerting: Bool

    public init(id: UUID, fireDate: Date?, ring: Ring?, alerting: Bool) {
        self.id = id
        self.fireDate = fireDate
        self.ring = ring
        self.alerting = alerting
    }
}

/// Everything that can change morning state. Time is always an input.
public enum Event: Equatable, Sendable {
    // Process lifecycle
    /// Cold start: the engine was just built from the persisted state.
    case launched(now: Date)
    case becameActive(now: Date)
    case enteredBackground(now: Date)
    /// The 5-second foreground loop.
    case tick(now: Date)

    // AlarmKit and intents
    /// The set of alarms alerting now changed. `coverVisible`: the morning cover is on screen (no sheet over it).
    case alerting(Set<UUID>, now: Date, audible: Bool, coverVisible: Bool)
    /// The cover finished presenting (home sheets dismissed). Takeover silencing may happen now.
    case coverShown(now: Date, audible: Bool)
    /// An alert button's intent ran. May arrive before or after `launched`/`becameActive`.
    case alertAction(ringID: UUID, AlertAction, now: Date)
    /// AlarmKit's current table, read after `.readSystemTable`.
    case systemTable([SystemAlarm], now: Date)
    /// The result of one `.schedule` effect.
    case scheduled(UUID, ok: Bool, now: Date)

    // In-app buttons
    case tapSnooze(UUID, now: Date)
    case tapNudgeStop(UUID, now: Date)
    case tapStartChallenge(UUID, now: Date)
    case solved(ringID: UUID, now: Date)
    case skip(ringID: UUID, now: Date)
    /// "I'm up" on the in-app awake check.
    case tapImUp(ringID: UUID, now: Date)
    case closeReleased(now: Date)
    /// The sensor for this kind is denied or failed: the open challenge falls back to math.
    case challengeUnavailable(ChallengeKind, now: Date)
    /// The sleeper is working on the open challenge: a keystroke, a step, a shake or a face sample (F4).
    case challengeActivity(now: Date)
    case bedsideChanged(Bool, now: Date)
    case chargingChanged(Bool, now: Date)

    // Configuration
    case settingsChanged(EngineSettings, now: Date)
    case calendarChanged(Calendar, now: Date)
}
