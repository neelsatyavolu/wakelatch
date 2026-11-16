import Foundation

/// What the morning full-screen cover shows. `.none` means home (or Bedside).
public enum Screen: Hashable, Sendable {
    case none
    /// A ring is due. `sounding` when it is alerting now. `snoozedUntil` is the next latched ring's date
    /// for a snoozable ring that is not sounding (D1), nil otherwise.
    case ringing(Ring, sounding: Bool, snoozedUntil: Date?)
    case challenge(ActiveChallenge)
    case awakeCheck(Ring)
    case released(MorningRecord)

    /// True for every case except `.none`.
    public var isShowing: Bool { self != .none }
}

/// The in-app chime.
public enum SoundCommand: Hashable, Sendable {
    /// Start (or keep) the chime. `nudge` picks the soft nudge sound.
    case play(nudge: Bool)
    /// Chime off. Used for home, snoozed ringing, challenge, released.
    case stop
}

/// A morning that has started and is not finished, for "under way" UI (D3).
public struct UnderWay: Hashable, Sendable {
    public let morning: Date
    public let deadline: Date
    /// The last latched ring plus grace: the morning ends as missed after this.
    public let endsBy: Date

    public init(morning: Date, deadline: Date, endsBy: Date) {
        self.morning = morning
        self.deadline = deadline
        self.endsBy = endsBy
    }
}

/// "Ring 3 of 10" numbering and the deadline for a ring's morning.
public struct RingPosition: Hashable, Sendable {
    public let number: Int
    public let total: Int
    public let deadline: Date?

    public init(number: Int, total: Int, deadline: Date?) {
        self.number = number
        self.total = total
        self.deadline = deadline
    }
}
