import Foundation

/// What a scheduled alarm is for. Raw values are stored in AlarmKit metadata, so they never change.
public enum RingKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Quiet heads-up before Ideal. Plain stop, no challenge.
    case nudge
    /// The first latched ring, at Ideal.
    case main
    /// Re-rings between Ideal and Deadline. The system Stop acts as a snooze.
    case snooze
    /// The Deadline ring. No snooze from here on.
    case deadline
    /// Every guard spacing after the Deadline until the challenge is done, or the guard window ends.
    case guardRing
    /// "Still up?" after a solve, with its own guards.
    case awakeCheck

    /// Latched rings keep coming until the morning's challenge is solved or skipped.
    public var latched: Bool { self != .nudge && self != .awakeCheck }

    /// Before the Deadline the ring can be snoozed (system Stop or in-app Snooze).
    public var allowsSnooze: Bool { self == .main || self == .snooze }
}

/// The challenge kinds a morning's rings were scheduled with.
public struct ChallengeSnapshot: Codable, Hashable, Sendable {
    /// Used by main and snooze rings.
    public var snooze: ChallengeKind
    /// Used by the deadline and guard rings.
    public var deadline: ChallengeKind

    public init(snooze: ChallengeKind, deadline: ChallengeKind) {
        self.snooze = snooze
        self.deadline = deadline
    }

    /// The kind a ring of `kind` carries: nil for nudges and awake checks.
    public func kind(for kind: RingKind) -> ChallengeKind? {
        switch kind {
        case .main, .snooze: snooze
        case .deadline, .guardRing: deadline
        case .nudge, .awakeCheck: nil
        }
    }
}

/// One alarm the engine wants AlarmKit to hold. Everything needed to rebuild it travels in its metadata.
public struct Ring: Codable, Hashable, Sendable, Identifiable {
    /// `RingIdentity.id(morning:kind:date:group:level:challenge:)`: the same ring always gets the same id.
    public let id: UUID
    public let date: Date
    public let kind: RingKind
    /// Challenge difficulty: 0 for nudges and awake checks, 1-2 before the Deadline, 3 from it.
    public let level: Int
    /// Ideal of the morning this ring belongs to.
    public let morning: Date
    /// For awake checks: which check (0, 1, ...) the ring belongs to. Nil otherwise.
    public let checkGroup: Int?
    /// The challenge kind snapshotted when the ring was planned. Nil for nudges and awake checks.
    public let challenge: ChallengeKind?

    public init(id: UUID, date: Date, kind: RingKind, level: Int, morning: Date,
                checkGroup: Int? = nil, challenge: ChallengeKind? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.level = level
        self.morning = morning
        self.checkGroup = checkGroup
        self.challenge = challenge
    }

    /// A ring whose id is derived from its morning, kind, date, group, level and challenge.
    public init(date: Date, kind: RingKind, level: Int, morning: Date,
                checkGroup: Int? = nil, challenge: ChallengeKind? = nil) {
        self.init(id: RingIdentity.id(morning: morning, kind: kind, date: date, group: checkGroup, level: level,
                                      challenge: challenge),
                  date: date, kind: kind, level: level, morning: morning,
                  checkGroup: checkGroup, challenge: challenge)
    }

    public var latched: Bool { kind.latched }
    public var allowsSnooze: Bool { kind.allowsSnooze }
}
