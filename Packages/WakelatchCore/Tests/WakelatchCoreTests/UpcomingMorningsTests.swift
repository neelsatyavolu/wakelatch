import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract A1-A4 and G3 through `MorningPlan.upcomingMornings`, plus the older Occurrences tests ported.
@Suite("A: which mornings are armed (upcomingMornings)")
struct UpcomingMorningsTests {
    let times = SimFixture.standard.settings.times
    let everyDay = Set(1...7)

    func upcoming(after now: Date, repeatDays: Set<Int>? = nil, count: Int = 3, active: Date? = nil,
                  oneOff: Date? = nil, times: WakeTimes? = nil, calendar: Calendar = Std.calendar) -> [Date] {
        MorningPlan.upcomingMornings(after: now, times: times ?? self.times, repeatDays: repeatDays ?? everyDay,
                                     count: count, excluding: active, oneOff: oneOff, calendar: calendar)
    }

    @Test("A1: the evening before, the next three mornings are armed")
    func eveningBefore() {
        #expect(upcoming(after: Std.t(21, 0, day: 15)) == [Std.ideal(day: 16), Std.ideal(day: 17), Std.ideal(day: 18)])
    }

    @Test("A1 (S01): with nudges on and Ideal 10 minutes away (first nudge passed), today is still armed")
    func idealTenMinutesAway() {
        #expect(upcoming(after: Std.t(6, 30)).first == Std.today)
        #expect(upcoming(after: Std.t(6, 25)).first == Std.today)
    }

    @Test("A1 (S02): Ideals strictly after now: one second before Ideal today counts, at Ideal it does not")
    func strictlyAfter() {
        #expect(upcoming(after: Std.t(6, 39, 59)).first == Std.today)
        #expect(upcoming(after: Std.t(6, 40)) == [Std.ideal(day: 17), Std.ideal(day: 18), Std.ideal(day: 19)])
    }

    @Test("A2: the calendar day of the active morning never yields a second morning")
    func activeDayExcluded() {
        let later = WakeTimes(ideal: ClockTime(hour: 7, minute: 30), deadline: ClockTime(hour: 8, minute: 0))
        let mornings = upcoming(after: Std.t(6, 45), active: Std.today, times: later)
        #expect(mornings == [Std.t(7, 30, day: 17), Std.t(7, 30, day: 18), Std.t(7, 30, day: 19)])
    }

    @Test("A3: weekdays only, from Friday morning: Monday, Tuesday, Wednesday")
    func weekdays() {
        let mornings = upcoming(after: Std.t(8, 0, day: 13), repeatDays: [2, 3, 4, 5, 6])
        #expect(mornings == [Std.ideal(day: 16), Std.ideal(day: 17), Std.ideal(day: 18)])
    }

    @Test("A3: only matching weekdays within 15 days: Sundays only from Monday 16th gives the 22nd and 29th")
    func fifteenDaySearch() {
        #expect(upcoming(after: Std.t(8, 0), repeatDays: [1]) == [Std.ideal(day: 22), Std.ideal(day: 29)])
    }

    @Test("A3: never more than count mornings")
    func countLimit() {
        #expect(upcoming(after: Std.t(21, 0, day: 15), count: 1) == [Std.today])
        #expect(upcoming(after: Std.t(21, 0, day: 15), count: 5).count == 5)
    }

    @Test("A4: one-off with nothing stored: the single next qualifying morning")
    func oneOffFirst() {
        #expect(upcoming(after: Std.t(22, 0, day: 12), repeatDays: []) == [Std.ideal(day: 13)])
        #expect(upcoming(after: Std.t(6, 0), repeatDays: []) == [Std.today])
    }

    @Test("A4: one-off stored and still ahead: exactly that morning")
    func oneOffStored() {
        #expect(upcoming(after: Std.t(6, 0), repeatDays: [], oneOff: Std.today) == [Std.today])
    }

    @Test("A4: one-off stored and passed: nothing")
    func oneOffPassed() {
        #expect(upcoming(after: Std.t(9, 0), repeatDays: [], oneOff: Std.today).isEmpty)
    }

    @Test("G4: in New York the same wall-clock times are New York mornings")
    func otherZone() {
        let mornings = upcoming(after: Std.t(21, 0, day: 15), count: 1, calendar: Std.newYork)
        #expect(mornings == [SimCalendar.date(2026, 11, 16, 6, 40, in: Std.newYork)])
    }
}
