import Foundation

/// A time of day, independent of date.
public struct ClockTime: Codable, Hashable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutes: Int { hour * 60 + minute }

    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }
}

/// When the user would like to be up, and when they must be.
public struct WakeTimes: Codable, Hashable, Sendable {
    public var ideal: ClockTime
    public var deadline: ClockTime

    public init(ideal: ClockTime, deadline: ClockTime) {
        self.ideal = ideal
        self.deadline = deadline
    }

    /// Minutes from Ideal to Deadline, wrapping past midnight.
    public var windowMinutes: Int {
        (deadline.minutes - ideal.minutes + 24 * 60) % (24 * 60)
    }
}

public struct PlanOptions: Codable, Hashable, Sendable {
    public static let maxSnoozeRings = 24

    public var nudges: Bool
    public var snoozeMinutes: Int
    public var guardRings: Int

    public init(nudges: Bool = true, snoozeMinutes: Int = 9, guardRings: Int = 15) {
        self.nudges = nudges
        self.snoozeMinutes = max(3, snoozeMinutes)
        self.guardRings = max(0, guardRings)
    }
}

public enum PlanError: Error, Equatable {
    case windowTooLong
}

public struct PlannedRing: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Quiet heads-up before Ideal. Plain stop.
        case nudge
        /// The first latched ring, at Ideal.
        case main
        /// Re-rings between Ideal and Deadline. Stop works as snooze.
        case snooze
        /// The Deadline ring. No snooze from here on.
        case deadline
        /// Every minute after the Deadline until the challenge is done.
        case guardRing
    }

    public let date: Date
    public let kind: Kind
    /// Challenge difficulty 1...3 (0 for nudges).
    public let level: Int

    public var latched: Bool { kind != .nudge }
    /// Before the Deadline the system Stop button acts as a snooze.
    public var allowsSnooze: Bool { kind == .main || kind == .snooze }
}

public enum MorningPlan {
    public static let maxWindowMinutes = 180
    static let nudgeOffsets = [20, 10]

    /// Every ring for the morning whose Ideal falls on `day`'s calendar date.
    public static func build(on day: Date, times: WakeTimes, options: PlanOptions,
                             calendar: Calendar) throws -> [PlannedRing] {
        let window = times.windowMinutes
        guard window <= maxWindowMinutes else { throw PlanError.windowTooLong }
        let ideal = idealDate(on: day, times: times, calendar: calendar)
        let deadline = ideal.addingTimeInterval(Double(window) * 60)

        var rings: [PlannedRing] = []
        if options.nudges {
            rings += nudgeOffsets.map {
                PlannedRing(date: ideal.addingTimeInterval(Double(-$0) * 60), kind: .nudge, level: 0)
            }
        }
        if window > 0 {
            rings.append(PlannedRing(date: ideal, kind: .main, level: 1))
            rings += snoozes(from: ideal, to: deadline, window: window, options: options)
        }
        rings.append(PlannedRing(date: deadline, kind: .deadline, level: 3))
        rings += (1...max(1, options.guardRings)).prefix(options.guardRings).map {
            PlannedRing(date: deadline.addingTimeInterval(Double($0) * 60), kind: .guardRing, level: 3)
        }
        return rings
    }

    private static func snoozes(from ideal: Date, to deadline: Date, window: Int,
                                options: PlanOptions) -> [PlannedRing] {
        // Long windows space rings out so a morning stays well under AlarmKit's budget.
        let spacing = max(options.snoozeMinutes, Int((Double(window) / Double(PlanOptions.maxSnoozeRings)).rounded(.up)))
        var rings: [PlannedRing] = []
        var minute = spacing
        while minute < window {
            let date = ideal.addingTimeInterval(Double(minute) * 60)
            if deadline.timeIntervalSince(date) < 60 { break }
            rings.append(PlannedRing(date: date, kind: .snooze, level: minute * 2 > window ? 2 : 1))
            minute += spacing
        }
        return rings
    }

    /// Ideal on `day`. A time skipped by a daylight-saving jump moves to the next valid time.
    public static func idealDate(on day: Date, times: WakeTimes, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: times.ideal.hour, minute: times.ideal.minute, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            ?? calendar.startOfDay(for: day)
    }

    /// The next `count` days whose morning hasn't started yet (first ring still ahead).
    /// `repeatDays` uses Calendar weekdays (1 = Sunday); empty means just the next morning.
    public static func upcomingDays(after now: Date, times: WakeTimes, repeatDays: Set<Int>, count: Int,
                                    nudges: Bool, calendar: Calendar) -> [Date] {
        let limit = repeatDays.isEmpty ? 1 : count
        let lead = Double(nudges ? (nudgeOffsets.max() ?? 0) : 0) * 60
        var days: [Date] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<15 where days.count < limit {
            let firstRing = idealDate(on: day, times: times, calendar: calendar).addingTimeInterval(-lead)
            let weekday = calendar.component(.weekday, from: day)
            if firstRing > now && (repeatDays.isEmpty || repeatDays.contains(weekday)) {
                days.append(day)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return days
    }
}

/// Short "are you still up?" alarms after the challenge is done.
public enum AwakeChecks {
    public static let offsetsMinutes = [5, 12]
    public static let guardsPerCheck = 3

    /// One array per check: the check itself followed by its guard rings, a minute apart.
    public static func plan(solvedAt: Date) -> [[Date]] {
        offsetsMinutes.map { offset in
            (0...guardsPerCheck).map { solvedAt.addingTimeInterval(Double(offset) * 60 + Double($0) * 60) }
        }
    }
}
