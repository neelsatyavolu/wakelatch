import Foundation
import WakelatchCore

/// Everything the user chooses. Stored as JSON in UserDefaults.
struct UserSettings: Codable, Equatable {
    var times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
    var enabled = true
    /// Calendar weekdays (1 = Sunday). Empty means only the next morning.
    var repeatDays: Set<Int> = Set(1...7)
    var plan = PlanOptions()
    var snoozeChallenge: ChallengeKind = .math
    var deadlineChallenge: ChallengeKind = .math
    var awakeChecks = true
    var bedsideKeepsScreenOn = true
    var onboarded = false

    func challenge(for ring: ScheduledRing) -> ChallengeKind {
        ring.level >= 3 ? deadlineChallenge : snoozeChallenge
    }
}

/// One alarm handed to AlarmKit, with what Wakelatch needs to know about it.
struct ScheduledRing: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case nudge, main, snooze, deadline, guardRing, awakeCheck
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let level: Int
    /// Ideal time of the morning this ring belongs to.
    let morning: Date
    /// For awake checks: which check (0, 1) the ring belongs to.
    var checkGroup: Int?

    var latched: Bool { kind != .nudge && kind != .awakeCheck }
    var allowsSnooze: Bool { kind == .main || kind == .snooze }

    init(id: UUID = UUID(), date: Date, kind: Kind, level: Int, morning: Date, checkGroup: Int? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.level = level
        self.morning = morning
        self.checkGroup = checkGroup
    }

    init(planned: PlannedRing, morning: Date) {
        let kind: Kind = switch planned.kind {
        case .nudge: .nudge
        case .main: .main
        case .snooze: .snooze
        case .deadline: .deadline
        case .guardRing: .guardRing
        }
        self.init(date: planned.date, kind: kind, level: planned.level, morning: morning)
    }
}

/// How a morning went, for the history line.
struct MorningRecord: Codable, Hashable {
    let morning: Date
    let ideal: Date
    let deadline: Date
    var upAt: Date?
    var skipped = false

    var upByIdeal: Bool { upAt.map { $0 <= ideal.addingTimeInterval(5 * 60) } ?? false }
    var upByDeadline: Bool { upAt.map { $0 <= deadline.addingTimeInterval(60) } ?? false }
}

/// JSON-in-UserDefaults storage for the few things Wakelatch keeps.
struct Storage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    func removeAll() {
        for key in ["settings", "rings", "records", "skips", "acknowledged"] { defaults.removeObject(forKey: key) }
    }
}
