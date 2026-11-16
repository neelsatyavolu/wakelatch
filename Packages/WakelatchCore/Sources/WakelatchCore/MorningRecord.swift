import Foundation

/// How a morning ended. Final once set.
public enum Outcome: String, Codable, Hashable, Sendable {
    case solved, skipped, missed
}

/// How a morning went, for the history line.
public struct MorningRecord: Codable, Hashable, Sendable {
    /// The morning's Ideal.
    public let morning: Date
    public let deadline: Date
    public let outcome: Outcome
    /// When the challenge was solved. Nil unless `outcome == .solved`.
    public let upAt: Date?

    public init(morning: Date, deadline: Date, outcome: Outcome, upAt: Date?) {
        self.morning = morning
        self.deadline = deadline
        self.outcome = outcome
        self.upAt = upAt
    }

    public var ideal: Date { morning }
    public var skipped: Bool { outcome == .skipped }
    /// Solved no later than five minutes after Ideal.
    public var upByIdeal: Bool { upAt.map { $0 <= morning.addingTimeInterval(5 * 60) } ?? false }
    /// Solved no later than a minute after the Deadline.
    public var upByDeadline: Bool { upAt.map { $0 <= deadline.addingTimeInterval(60) } ?? false }
}
