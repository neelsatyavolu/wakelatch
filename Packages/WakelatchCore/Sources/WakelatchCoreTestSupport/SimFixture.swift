import Foundation
import WakelatchCore

/// Fixed calendars and date helpers, so no test reads the machine's time zone.
public enum SimCalendar {
    /// Gregorian, America/Los_Angeles (has DST: 2026-03-08 spring forward, 2026-11-01 fall back).
    public static let losAngeles: Calendar = make("America/Los_Angeles")
    /// Gregorian, UTC.
    public static let utc: Calendar = make("UTC")

    public static func make(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        return calendar
    }

    /// A wall-clock instant in `calendar`.
    public static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                            _ second: Int = 0, in calendar: Calendar = losAngeles) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}

/// The settings and calendar a simulated morning runs with.
public struct SimFixture: Sendable {
    public var settings: EngineSettings
    public var calendar: Calendar

    public init(settings: EngineSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Ideal 06:40, Deadline 07:10, nudges on, 9-minute snooze, every day, awake checks on, Math/Math,
    /// Los Angeles. Rings: nudges 06:20, 06:30; main 06:40; snoozes 06:49 (L1), 06:58 (L2), 07:07 (L2);
    /// deadline 07:10; guards 07:11 through 08:10; missed after 08:20.
    public static let standard = SimFixture(
        settings: EngineSettings(
            times: WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10)),
            repeatDays: Set(1...7),
            enabled: true,
            timing: .production(PlanOptions()),
            snoozeChallenge: .math,
            deadlineChallenge: .math,
            awakeChecks: true,
            keepScreenOn: true),
        calendar: SimCalendar.losAngeles)

    /// Returns a copy with `change` applied.
    public func with(_ change: (inout SimFixture) -> Void) -> SimFixture {
        var copy = self
        change(&copy)
        return copy
    }
}
