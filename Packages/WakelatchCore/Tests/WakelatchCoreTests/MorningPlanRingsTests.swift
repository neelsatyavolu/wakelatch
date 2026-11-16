import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract T6, T7 and I2 through `MorningPlan.build(on:times:timing:challenges:calendar:)`, plus the older
/// MorningPlan tests ported to the ring API.
@Suite("T7: building a calendar day's morning")
struct MorningPlanRingsTests {
    let calendar = SimCalendar.losAngeles
    let math = ChallengeSnapshot(snooze: .math, deadline: .math)
    let production = PlanTiming.production(PlanOptions())

    func times(_ ideal: (Int, Int), _ deadline: (Int, Int)) -> WakeTimes {
        WakeTimes(ideal: ClockTime(hour: ideal.0, minute: ideal.1), deadline: ClockTime(hour: deadline.0, minute: deadline.1))
    }

    func build(_ ideal: (Int, Int), _ deadline: (Int, Int), on day: Date, timing: PlanTiming? = nil,
               calendar: Calendar? = nil) throws -> [Ring] {
        try MorningPlan.build(on: day, times: times(ideal, deadline), timing: timing ?? production,
                              challenges: math, calendar: calendar ?? self.calendar)
    }

    @Test("T7: the day's Ideal comes from the injected calendar; the whole morning matches the hand-written plan")
    func standardDay() throws {
        let rings = try build((6, 40), (7, 10), on: Std.t(12, 0))
        #expect(rings == Std.morning())
    }

    @Test("T7: the same wall-clock times in New York give a morning three hours earlier in absolute time")
    func otherZone() throws {
        let rings = try build((6, 40), (7, 10), on: Std.t(12, 0), calendar: Std.newYork)
        let main = try #require(rings.first { $0.kind == .main })
        #expect(main.date == SimCalendar.date(2026, 11, 16, 6, 40, in: Std.newYork))
        #expect(main.date == Std.t(3, 40))
    }

    @Test("T6: a window longer than 180 minutes is refused with windowTooLong")
    func tooLong() {
        #expect(throws: PlanError.windowTooLong) {
            _ = try build((5, 0), (8, 1), on: Std.t(12, 0))
        }
    }

    @Test("T6: exactly 180 minutes is allowed")
    func maxWindow() throws {
        let rings = try build((5, 0), (8, 0), on: Std.t(12, 0))
        #expect(rings.first { $0.kind == .deadline }?.date == Std.t(8, 0))
    }

    @Test("T7: a deadline after midnight lands on the next calendar day")
    func crossesMidnight() throws {
        let rings = try build((23, 50), (0, 20), on: Std.t(12, 0))
        #expect(rings.first { $0.kind == .main }?.date == Std.t(23, 50))
        #expect(rings.first { $0.kind == .deadline }?.date == Std.t(0, 20, day: 17))
    }

    @Test("T7: an Ideal in the spring-forward gap (02:30 on 2026-03-08) moves to the next valid time")
    func springForward() throws {
        let rings = try build((2, 30), (3, 30), on: SimCalendar.date(2026, 3, 8, 12, 0))
        let main = try #require(rings.first { $0.kind == .main })
        #expect(calendar.component(.hour, from: main.date) == 3)
        #expect(main.date >= SimCalendar.date(2026, 3, 8, 3, 0))
        #expect(rings.map(\.date) == rings.map(\.date).sorted())
        #expect(Set(rings.map(\.id)).count == rings.count)
    }

    @Test("T7: an Ideal in the repeated fall-back hour (01:30 on 2026-11-01) uses the first occurrence, PDT")
    func fallBackFirstOccurrence() throws {
        let rings = try build((1, 30), (2, 0), on: SimCalendar.date(2026, 11, 1, 12, 0))
        let main = try #require(rings.first { $0.kind == .main })
        #expect(main.date == SimCalendar.date(2026, 11, 1, 8, 30, in: SimCalendar.utc))
    }

    @Test("T7 (S20): a fall-back morning has 67 rings with distinct ids in strictly increasing time")
    func fallBackNoDuplicates() throws {
        let rings = try build((1, 30), (2, 0), on: SimCalendar.date(2026, 11, 1, 12, 0))
        #expect(rings.count == 67)
        #expect(Set(rings.map(\.id)).count == 67)
        #expect(zip(rings, rings.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test("I2: building the same morning twice gives identical ids")
    func deterministicIDs() throws {
        let first = try build((6, 40), (7, 10), on: Std.t(12, 0))
        let second = try build((6, 40), (7, 10), on: Std.t(9, 0))
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test("I2: a different morning or time gives different ids")
    func idsChangeWithMorning() throws {
        let monday = Set(try build((6, 40), (7, 10), on: Std.t(12, 0)).map(\.id))
        let tuesday = Set(try build((6, 40), (7, 10), on: Std.t(12, 0, day: 17)).map(\.id))
        let later = Set(try build((6, 45), (7, 15), on: Std.t(12, 0)).map(\.id))
        #expect(monday.isDisjoint(with: tuesday))
        #expect(monday.isDisjoint(with: later))
    }

    @Test("T3: windowOverride replaces the WakeTimes window")
    func windowOverride() throws {
        let rings = try build((6, 40), (7, 10), on: Std.t(12, 0), timing: .compressed)
        let main = try #require(rings.first { $0.kind == .main })
        #expect(rings.first { $0.kind == .deadline }?.date == main.date.addingTimeInterval(120))
        #expect(MorningPlan.window(times: times((6, 40), (7, 10)), timing: .compressed) == 120)
        #expect(MorningPlan.window(times: times((6, 40), (7, 10)), timing: production) == 1800)
    }

    @Test("A7: a full three-hour morning with 3-minute snoozes is 87 rings, so 2 mornings fit the 250 budget")
    func threeHourMorning() throws {
        let timing = PlanTiming.production(PlanOptions(snoozeMinutes: 3))
        let rings = try build((5, 0), (8, 0), on: Std.t(12, 0), timing: timing)
        #expect(rings.count == 87)
        #expect(rings.count * 2 <= ScheduleBudget.limit)
        #expect(ScheduleBudget.limit == 250)
    }

    @Test("I3: a ring survives an encode/decode round trip unchanged (its metadata rebuilds it)")
    func ringCodable() throws {
        let ring = Std.awake(group: 1, index: 2, solvedAt: Std.t(6, 41))
        let data = try JSONEncoder().encode(ring)
        #expect(try JSONDecoder().decode(Ring.self, from: data) == ring)
        let guardRing = Std.guardRing(5, kind: .shake)
        #expect(try JSONDecoder().decode(Ring.self, from: JSONEncoder().encode(guardRing)) == guardRing)
    }
}
