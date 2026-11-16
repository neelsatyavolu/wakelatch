import Foundation

/// The user's choices as the engine needs them. An input: the engine never reads UserDefaults.
public struct EngineSettings: Codable, Hashable, Sendable {
    public var times: WakeTimes
    /// Calendar weekdays (1 = Sunday). Empty means a one-off morning.
    public var repeatDays: Set<Int>
    public var enabled: Bool
    public var timing: PlanTiming
    public var snoozeChallenge: ChallengeKind
    public var deadlineChallenge: ChallengeKind
    public var awakeChecks: Bool
    public var keepScreenOn: Bool
    /// How many mornings ahead are armed.
    public var armedMornings: Int
    /// UI tests: one morning with its Ideal at exactly this instant, instead of `times` and `repeatDays`.
    public var pinnedMorning: Date?

    public init(times: WakeTimes, repeatDays: Set<Int>, enabled: Bool, timing: PlanTiming,
                snoozeChallenge: ChallengeKind, deadlineChallenge: ChallengeKind,
                awakeChecks: Bool, keepScreenOn: Bool, armedMornings: Int = 3, pinnedMorning: Date? = nil) {
        self.times = times
        self.repeatDays = repeatDays
        self.enabled = enabled
        self.timing = timing
        self.snoozeChallenge = snoozeChallenge
        self.deadlineChallenge = deadlineChallenge
        self.awakeChecks = awakeChecks
        self.keepScreenOn = keepScreenOn
        self.armedMornings = armedMornings
        self.pinnedMorning = pinnedMorning
    }

    /// The kinds snapshotted onto rings planned with these settings.
    public var challenges: ChallengeSnapshot {
        ChallengeSnapshot(snooze: snoozeChallenge, deadline: deadlineChallenge)
    }
}
