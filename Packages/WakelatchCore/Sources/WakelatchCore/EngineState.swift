import Foundation

/// An alert button asked to open the challenge for `ringID`. Persisted so a cold launch honours it.
public struct PendingRoute: Codable, Hashable, Sendable {
    public let ringID: UUID
    public let at: Date

    public init(ringID: UUID, at: Date) {
        self.ringID = ringID
        self.at = at
    }
}

/// The challenge the user has open. Persisted, so cold and warm launches land on the same challenge.
public struct ActiveChallenge: Codable, Hashable, Sendable {
    /// The latest due latched ring when the challenge last started or upgraded. The view is keyed by its id.
    public let ring: Ring
    /// The ring's snapshotted kind, or `.math` after `challengeUnavailable`.
    public let kind: ChallengeKind

    public init(ring: Ring, kind: ChallengeKind) {
        self.ring = ring
        self.kind = kind
    }

    public var level: Int { ring.level }
    public var morning: Date { ring.morning }
}

/// Everything about mornings that survives a kill. `MorningEngine.handle` is its only writer, and the
/// app saves it (the `.persist` effect) before running any other effect of the same event.
public struct EngineState: Codable, Equatable, Sendable {
    /// What AlarmKit should hold, past rings of unfinished mornings included. Source of truth.
    public var target: [Ring]
    /// Ids handed to AlarmKit whose result has not come back. Never cancelled as unknown.
    public var pendingSchedule: Set<UUID>
    /// Ids whose last schedule attempt failed; retried on the next reconcile.
    public var failedSchedule: Set<UUID>
    /// Rings snoozed in-app, nudges stopped in-app, and awake-check rings confirmed.
    public var acknowledged: Set<UUID>
    /// Morning (Ideal) to outcome. Never overwritten.
    public var finished: [Date: Outcome]
    /// One per finished morning, oldest first, at most `EngineState.recordLimit`.
    public var records: [MorningRecord]
    public var skips: SkipLedger
    public var challenge: ActiveChallenge?
    public var route: PendingRoute?
    /// The single morning armed while repeat days are empty. Finishing it turns the alarm off.
    public var oneOffMorning: Date?
    /// When a finished one-off turned the alarm off (A4). Until the app's settings say `enabled == false`
    /// (it saved the turn-off), settings saying enabled are stale: the engine keeps the alarm off and sends
    /// `.disableAlarm` again. Persisted, so a kill before the app saved the turn-off cannot re-arm it.
    public var turnedOff: Date?
    /// When this state first went through a reconcile pass. Nil: it has never seen AlarmKit's table (a new
    /// install, or state lost or reset), so the first pass adopts a morning under way it finds there (R2).
    public var firstPass: Date?

    public static let recordLimit = 60

    public init(target: [Ring] = [], pendingSchedule: Set<UUID> = [], failedSchedule: Set<UUID> = [],
                acknowledged: Set<UUID> = [], finished: [Date: Outcome] = [:], records: [MorningRecord] = [],
                skips: SkipLedger = SkipLedger(), challenge: ActiveChallenge? = nil, route: PendingRoute? = nil,
                oneOffMorning: Date? = nil, turnedOff: Date? = nil, firstPass: Date? = nil) {
        self.target = target
        self.pendingSchedule = pendingSchedule
        self.failedSchedule = failedSchedule
        self.acknowledged = acknowledged
        self.finished = finished
        self.records = records
        self.skips = skips
        self.challenge = challenge
        self.route = route
        self.oneOffMorning = oneOffMorning
        self.turnedOff = turnedOff
        self.firstPass = firstPass
    }
}

/// A nudge the in-app screen is showing, and since when.
public struct NudgeOnScreen: Hashable, Sendable {
    public let ringID: UUID
    public let since: Date

    public init(ringID: UUID, since: Date) {
        self.ringID = ringID
        self.since = since
    }
}

/// The Released screen and when the morning was solved.
public struct ReleasedOnScreen: Hashable, Sendable {
    public let record: MorningRecord
    public let since: Date

    public init(record: MorningRecord, since: Date) {
        self.record = record
        self.since = since
    }
}

/// Per-process state. Never persisted: `launched` starts from `SessionState()`, and `enteredBackground`
/// clears everything a new visit must not inherit, which is what makes cold and warm launches equal.
public struct SessionState: Equatable, Sendable {
    public var appActive: Bool
    /// System alarms alerting right now, from `alerting` and `systemTable` events.
    public var alerting: Set<UUID>
    /// Rings the app silenced on takeover (F3). They keep the in-app screen sounding after the system alarm
    /// stops, until tapped or the app leaves the foreground.
    public var takenOver: Set<UUID>
    public var coverVisible: Bool
    public var audible: Bool
    public var bedside: Bool
    public var charging: Bool
    /// A ring snoozed in-app during this visit: home is shown until a newer ring is due.
    public var dismissedThisVisit: UUID?
    public var nudge: NudgeOnScreen?
    public var released: ReleasedOnScreen?
    /// The last time the sleeper worked on the open challenge (opening it counts). An open challenge only
    /// silences rings while this is recent (F4).
    public var challengeActivity: Date?
    public var screen: Screen
    /// Last value sent with `setIdleTimerDisabled`, so it is only sent on change.
    public var idleTimerDisabled: Bool
    /// Last sound command sent, so it is only sent on change.
    public var sound: SoundCommand
    /// This process already asked for AlarmKit's table. A new process reads it on its first event, whatever
    /// that event is (R1), since a background intent can start one that never receives `launched`.
    public var tableRequested: Bool
    /// When this process last asked for AlarmKit's table, for the failed-schedule retry backoff (R4).
    public var lastReadRequest: Date?
    /// Reconcile passes this process ran, and whether it sent its one confirming read (R1): a call a killed
    /// process had already sent can land just after this process's first read.
    public var passes: Int
    public var confirmReadSent: Bool

    public init(appActive: Bool = false, alerting: Set<UUID> = [], takenOver: Set<UUID> = [],
                coverVisible: Bool = false,
                audible: Bool = false, bedside: Bool = false, charging: Bool = false,
                dismissedThisVisit: UUID? = nil, nudge: NudgeOnScreen? = nil, released: ReleasedOnScreen? = nil,
                screen: Screen = .none, idleTimerDisabled: Bool = false, sound: SoundCommand = .stop,
                tableRequested: Bool = false, lastReadRequest: Date? = nil, passes: Int = 0,
                confirmReadSent: Bool = false) {
        self.appActive = appActive
        self.alerting = alerting
        self.takenOver = takenOver
        self.coverVisible = coverVisible
        self.audible = audible
        self.bedside = bedside
        self.charging = charging
        self.dismissedThisVisit = dismissedThisVisit
        self.nudge = nudge
        self.released = released
        self.challengeActivity = nil
        self.screen = screen
        self.idleTimerDisabled = idleTimerDisabled
        self.sound = sound
        self.tableRequested = tableRequested
        self.lastReadRequest = lastReadRequest
        self.passes = passes
        self.confirmReadSent = confirmReadSent
    }
}
