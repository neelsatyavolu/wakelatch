import Foundation
import Testing
@testable import WakelatchCore

@Suite("MorningPlan")
struct MorningPlanTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func plan(_ ideal: (Int, Int), _ deadline: (Int, Int), on date: Date,
              options: PlanOptions = PlanOptions()) throws -> [PlannedRing] {
        try MorningPlan.build(
            on: date,
            times: WakeTimes(ideal: ClockTime(hour: ideal.0, minute: ideal.1),
                             deadline: ClockTime(hour: deadline.0, minute: deadline.1)),
            options: options, calendar: calendar)
    }

    @Test("a 30-minute window: nudges, latch every 9 min, deadline, then guards")
    func standardMorning() throws {
        let rings = try plan((6, 40), (7, 10), on: day(2026, 11, 13))
        let nudges = rings.filter { $0.kind == .nudge }
        #expect(nudges.map(\.date) == [at(2026, 11, 13, 6, 20), at(2026, 11, 13, 6, 30)])
        #expect(nudges.allSatisfy { !$0.latched })

        let window = rings.filter { $0.kind == .main || $0.kind == .snooze }
        #expect(window.map(\.date) == [
            at(2026, 11, 13, 6, 40), at(2026, 11, 13, 6, 49),
            at(2026, 11, 13, 6, 58), at(2026, 11, 13, 7, 7),
        ])
        #expect(rings.first { $0.kind == .main }?.level == 1)

        let deadline = try #require(rings.first { $0.kind == .deadline })
        #expect(deadline.date == at(2026, 11, 13, 7, 10))
        #expect(deadline.level == 3)

        let guards = rings.filter { $0.kind == .guardRing }
        #expect(guards.count == 15)
        #expect(guards.first?.date == at(2026, 11, 13, 7, 11))
        #expect(guards.last?.date == at(2026, 11, 13, 7, 25))
        let latched = rings.filter { $0.kind != .nudge }.allSatisfy { $0.latched }
        #expect(latched)
    }

    @Test("rings are in time order")
    func ordered() throws {
        let rings = try plan((6, 40), (7, 10), on: day(2026, 11, 13))
        #expect(rings.map(\.date) == rings.map(\.date).sorted())
    }

    @Test("a snooze ring less than a minute before the deadline is dropped")
    func dropsCrowdedSnooze() throws {
        let rings = try plan((7, 0), (7, 18), on: day(2026, 11, 13), options: PlanOptions(snoozeMinutes: 9))
        // 7:00, 7:09; 7:18 is the deadline itself
        #expect(rings.filter { $0.kind == .snooze }.map(\.date) == [at(2026, 11, 13, 7, 9)])
    }

    @Test("later snoozes get harder")
    func levels() throws {
        let rings = try plan((6, 0), (7, 0), on: day(2026, 11, 13))
        let snoozes = rings.filter { $0.kind == .snooze }
        #expect(snoozes.first?.level == 1)
        #expect(snoozes.last?.level == 2)
    }

    @Test("ideal equal to deadline: one latched deadline ring, no snoozes")
    func sameTime() throws {
        let rings = try plan((7, 0), (7, 0), on: day(2026, 11, 13))
        #expect(rings.filter { $0.kind == .main || $0.kind == .snooze }.isEmpty)
        #expect(rings.first { $0.kind == .deadline }?.date == at(2026, 11, 13, 7, 0))
        #expect(rings.filter { $0.kind == .nudge }.count == 2)
    }

    @Test("nudges can be turned off")
    func noNudges() throws {
        let rings = try plan((6, 40), (7, 10), on: day(2026, 11, 13), options: PlanOptions(nudges: false))
        #expect(rings.allSatisfy { $0.kind != .nudge })
    }

    @Test("a deadline after midnight lands on the next day")
    func crossesMidnight() throws {
        let rings = try plan((23, 50), (0, 20), on: day(2026, 11, 13))
        #expect(rings.first { $0.kind == .deadline }?.date == at(2026, 11, 14, 0, 20))
    }

    @Test("a window longer than three hours is refused")
    func tooLong() {
        #expect(throws: PlanError.windowTooLong) {
            _ = try plan((5, 0), (8, 1), on: day(2026, 11, 13))
        }
    }

    @Test("spring-forward gap: 2:30 doesn't exist, the ring moves to 3:00 or later")
    func springForward() throws {
        let rings = try plan((2, 30), (3, 30), on: day(2026, 3, 8))
        let main = try #require(rings.first { $0.kind == .main })
        #expect(calendar.component(.hour, from: main.date) == 3)
        #expect(rings.map(\.date) == rings.map(\.date).sorted())
    }

    @Test("a full three-hour morning stays under 45 rings")
    func ringBudget() throws {
        let rings = try plan((5, 0), (8, 0), on: day(2026, 11, 13), options: PlanOptions(snoozeMinutes: 5))
        #expect(rings.count <= 45)
    }

    @Test("snooze interval below 3 minutes is clamped")
    func clampSnooze() {
        #expect(PlanOptions(snoozeMinutes: 1).snoozeMinutes == 3)
    }
}

@Suite("Occurrences")
struct OccurrenceTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    let times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))

    func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }

    @Test("no repeat days: the next morning only")
    func once() {
        // Thursday 2026-11-12 22:00
        let days = MorningPlan.upcomingDays(after: at(11, 12, 22, 0), times: times, repeatDays: [],
                                            count: 3, nudges: true, calendar: calendar)
        #expect(days.count == 1)
        #expect(calendar.component(.day, from: days[0]) == 13)
    }

    @Test("today still counts before its first nudge")
    func todayBeforeNudge() {
        let days = MorningPlan.upcomingDays(after: at(11, 12, 6, 0), times: times, repeatDays: [],
                                            count: 1, nudges: true, calendar: calendar)
        #expect(calendar.component(.day, from: days[0]) == 12)
    }

    @Test("today is skipped once its first nudge has passed")
    func todayAfterNudge() {
        let days = MorningPlan.upcomingDays(after: at(11, 12, 6, 25), times: times, repeatDays: [],
                                            count: 1, nudges: true, calendar: calendar)
        #expect(calendar.component(.day, from: days[0]) == 13)
    }

    @Test("weekdays only skips the weekend")
    func weekdays() {
        // Friday 2026-11-13 08:00 → Mon 16, Tue 17, Wed 18
        let days = MorningPlan.upcomingDays(after: at(11, 13, 8, 0), times: times, repeatDays: [2, 3, 4, 5, 6],
                                            count: 3, nudges: true, calendar: calendar)
        #expect(days.map { calendar.component(.day, from: $0) } == [16, 17, 18])
    }
}
