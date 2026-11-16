import Foundation
import WakelatchCore
import WakelatchCoreTestSupport

/// The standard morning (SimFixture.standard) written out by hand from the contract, so tests compare the
/// engine against independent expectations. Los Angeles, November 2026 (PST). Ideal 06:40, Deadline 07:10:
/// nudges 06:20 and 06:30 (L0); main 06:40 (L1); snoozes 06:49 (L1), 06:58 (L2), 07:07 (L2); deadline 07:10 (L3);
/// guards every minute 07:11 through 08:10 (L3); the morning ends as missed after 08:20.
/// Rings are keyed by their morning's Ideal, so `Std.main(of: Std.ideal(day: 17))` is Tuesday's main.
enum Std {
    static let calendar = SimCalendar.losAngeles

    /// A wall-clock time in Los Angeles. Day 15 is Sunday 2026-11-15, day 16 is Monday.
    static func t(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 16, month: Int = 11,
                  year: Int = 2026) -> Date {
        SimCalendar.date(year, month, day, hour, minute, second, in: calendar)
    }

    static func ideal(day: Int = 16, month: Int = 11) -> Date { t(6, 40, day: day, month: month) }
    static let today = ideal()
    static let window: TimeInterval = 30 * 60
    static let snoozeOffsets: [TimeInterval] = [540, 1080, 1620]
    static let snoozeLevels = [1, 2, 2]
    static let guardCount = 60

    static func deadlineDate(of morning: Date = today) -> Date { morning.addingTimeInterval(window) }
    static func endsBy(of morning: Date = today) -> Date { deadlineDate(of: morning).addingTimeInterval(70 * 60) }

    static func nudge(_ index: Int, of morning: Date = today) -> Ring {
        Ring(date: morning.addingTimeInterval(index == 0 ? -1200 : -600), kind: .nudge, level: 0, morning: morning)
    }

    static func main(of morning: Date = today, kind: ChallengeKind = .math) -> Ring {
        Ring(date: morning, kind: .main, level: 1, morning: morning, challenge: kind)
    }

    /// Snooze 0 (06:49, L1), 1 (06:58, L2) or 2 (07:07, L2).
    static func snooze(_ index: Int, of morning: Date = today, kind: ChallengeKind = .math) -> Ring {
        Ring(date: morning.addingTimeInterval(snoozeOffsets[index]), kind: .snooze, level: snoozeLevels[index],
             morning: morning, challenge: kind)
    }

    static func deadline(of morning: Date = today, kind: ChallengeKind = .math) -> Ring {
        Ring(date: deadlineDate(of: morning), kind: .deadline, level: 3, morning: morning, challenge: kind)
    }

    /// Guard `number` (1...60) rings `number` minutes after the deadline.
    static func guardRing(_ number: Int, of morning: Date = today, kind: ChallengeKind = .math) -> Ring {
        Ring(date: deadlineDate(of: morning).addingTimeInterval(Double(number) * 60), kind: .guardRing, level: 3,
             morning: morning, challenge: kind)
    }

    static func guards(of morning: Date = today, kind: ChallengeKind = .math) -> [Ring] {
        (1...guardCount).map { guardRing($0, of: morning, kind: kind) }
    }

    /// Main, the three snoozes, the deadline and 60 guards.
    static func latched(of morning: Date = today, snooze: ChallengeKind = .math,
                        deadline deadlineKind: ChallengeKind = .math) -> [Ring] {
        [main(of: morning, kind: snooze)] + (0..<3).map { self.snooze($0, of: morning, kind: snooze) }
            + [deadline(of: morning, kind: deadlineKind)] + guards(of: morning, kind: deadlineKind)
    }

    /// Every ring of a standard morning, oldest first (67 with nudges).
    static func morning(_ morning: Date = today, nudges: Bool = true, snooze: ChallengeKind = .math,
                        deadline: ChallengeKind = .math) -> [Ring] {
        (nudges ? [nudge(0, of: morning), nudge(1, of: morning)] : [])
            + latched(of: morning, snooze: snooze, deadline: deadline)
    }

    /// Awake check `index` (0 is the check, 1-3 its guards) of `group` (0: +5 min, 1: +12 min).
    static func awake(group: Int, index: Int, solvedAt: Date, of morning: Date = today) -> Ring {
        let offset: TimeInterval = group == 0 ? 300 : 720
        return Ring(date: solvedAt.addingTimeInterval(offset + Double(index) * 60), kind: .awakeCheck, level: 0,
                    morning: morning, checkGroup: group)
    }

    static func awakeGroup(_ group: Int, solvedAt: Date, of morning: Date = today) -> [Ring] {
        (0...3).map { awake(group: group, index: $0, solvedAt: solvedAt, of: morning) }
    }

    static func awakeChecks(solvedAt: Date, of morning: Date = today) -> [Ring] {
        awakeGroup(0, solvedAt: solvedAt, of: morning) + awakeGroup(1, solvedAt: solvedAt, of: morning)
    }

    static func record(_ outcome: Outcome, of morning: Date = today, upAt: Date? = nil) -> MorningRecord {
        MorningRecord(morning: morning, deadline: deadlineDate(of: morning), outcome: outcome, upAt: upAt)
    }

    static let newYork = SimCalendar.make("America/New_York")
}

extension SimFixture {
    /// The standard fixture with its settings changed.
    static func standard(_ change: (inout EngineSettings) -> Void) -> SimFixture {
        SimFixture.standard.with { change(&$0.settings) }
    }

    /// The standard fixture without nudges.
    static let noNudges = SimFixture.standard { $0.timing = .production(PlanOptions(nudges: false)) }
}
