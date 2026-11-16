import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group S, S12-S22: crashes mid-reconcile, adoption, failures, budget, time zones, DST, guards until solved (D2).
@Suite("S: recovery, budget, time zones and guards")
struct RecoveryTests {
    static let threeHours = SimFixture.standard {
        $0.times = WakeTimes(ideal: ClockTime(hour: 5, minute: 0), deadline: ClockTime(hour: 8, minute: 0))
        $0.timing = .production(PlanOptions(snoozeMinutes: 3))
    }

    @Test("S12 (R5): killed after any effect of the first sync, the next launch completes the schedule exactly",
          arguments: [0, 1, 2, 3, 4, 5, 8, 13, 21, 34, 55, 89, 144, 200, 233, 300, 377, 450, 610])
    func s12(killAfter: Int) {
        var sim = MorningSim(start: Std.t(21, 0, day: 15))
        sim.killAfter(effects: killAfter)
        sim.launch()
        sim.suspend()
        sim.advance(by: 10)
        sim.kill()
        sim.open()
        let expected = Std.morning() + Std.morning(Std.ideal(day: 17)) + Std.morning(Std.ideal(day: 18))
        #expect(sim.system.ids == ids(expected))
        expectClean(sim)
    }

    enum Trigger: String, CaseIterable, Sendable { case reopen, settingsChange }

    @Test("S13 (R5, INV3): a kill at any point of a mid-morning sync never removes today's chain",
          arguments: Trigger.allCases)
    func s13(trigger: Trigger) throws {
        let dry = Self.s13Effects(trigger)
        let firstCancel = try #require(dry.firstIndex { if case .cancel = $0 { true } else { false } })
        let lastCancel = try #require(dry.lastIndex { if case .cancel = $0 { true } else { false } })
        let points = Set([0, 1, 2, firstCancel - 1, firstCancel, firstCancel + 1, (firstCancel + lastCancel) / 2,
                          lastCancel, dry.count - 2]).filter { $0 >= 0 && $0 < dry.count - 1 }.sorted()
        for killAfter in points {
            var sim = Self.s13Setup(trigger)
            sim.killAfter(effects: killAfter)
            Self.s13Trigger(&sim, trigger)
            try #require(sim.engine == nil, "kill after effect \(killAfter) of \(dry.count) lands inside the sync")
            sim.open()
            let future = [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] + Std.guards()
            #expect(ids(future).isSubset(of: sim.system.ids), "kill after \(killAfter)")
            #expect(sim.state.finished[Std.today] == nil)
            expectClean(sim)
        }
    }

    /// 06:45 with today under way. `reopen` starts suspended with stale alarms of other mornings planted, so
    /// its pass has cancels; `settingsChange` starts in the foreground.
    static func s13Setup(_ trigger: Trigger) -> MorningSim {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        switch trigger {
        case .reopen:
            for number in 1...6 { sim.plant(Std.guardRing(number, of: Std.ideal(day: 12)).withDate(Std.t(9, number))) }
            sim.plant(Std.main(of: Std.ideal(day: 19)))
        case .settingsChange:
            sim.open()
            sim.settle()
        }
        return sim
    }

    static func s13Trigger(_ sim: inout MorningSim, _ trigger: Trigger) {
        switch trigger {
        case .reopen:
            sim.open()
        case .settingsChange:
            sim.changeSettings {
                $0.times = WakeTimes(ideal: ClockTime(hour: 7, minute: 0), deadline: ClockTime(hour: 7, minute: 30))
            }
        }
    }

    /// Every effect the trigger's sync runs, from a run without faults.
    static func s13Effects(_ trigger: Trigger) -> [Effect] {
        var sim = s13Setup(trigger)
        let mark = sim.effectLog.count
        s13Trigger(&sim, trigger)
        sim.settle()
        return sim.effects(since: mark)
    }

    @Test("S14 (R2.1): an unknown future latched alarm of the active morning is adopted into target and kept")
    func s14() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.kill()
        let extra = Ring(date: Std.t(7, 30, 30), kind: .guardRing, level: 3, morning: Std.today, challenge: .math)
        sim.plant(extra)
        sim.open()
        #expect(sim.state.target.contains(extra))
        #expect(sim.system.contains(extra.id))
        expectClean(sim)
    }

    @Test("S15: an orphan of another morning and an alarm without metadata are cancelled")
    func s15() {
        var sim = MorningSim.armed()
        sim.kill()
        let orphan = Std.guardRing(5, of: Std.ideal(day: 15)).withDate(Std.t(9, 0))
        let foreign = UUID()
        sim.plant(orphan)
        sim.plantForeign(id: foreign, fireDate: Std.t(9, 0))
        sim.open()
        #expect(!sim.system.contains(orphan.id))
        #expect(!sim.system.contains(foreign))
        expectClean(sim)
    }

    @Test("S16 (R4): a failed schedule is reported and retried on the next pass; success clears the error")
    func s16() {
        let deadline = Std.deadline()
        var sim = MorningSim(start: Std.t(21, 0, day: 15), faults: SimFaults(scheduleFails: [deadline.id]))
        sim.launch()
        #expect(sim.engine?.hasScheduleError == true)
        #expect(sim.state.failedSchedule == [deadline.id])
        #expect(!sim.system.contains(deadline.id))
        sim.faults.scheduleFails = []
        sim.suspend()
        sim.open()
        #expect(sim.system.contains(deadline.id))
        #expect(sim.engine?.hasScheduleError == false)
        expectClean(sim)
    }

    @Test("S17 (A7, D2): three 3-hour mornings are trimmed to 250 alarms from the farthest morning's latest guards")
    func s17() {
        var sim = MorningSim(fixture: Self.threeHours, start: Std.t(21, 0, day: 15))
        sim.launch()
        #expect(sim.system.ids.count == ScheduleBudget.limit)
        #expect(guardDates(sim, day: 16).count == 60)
        #expect(guardDates(sim, day: 17).count == 60)
        #expect(guardDates(sim, day: 18) == (1...49).map { Std.t(8, 0, day: 18).addingTimeInterval(Double($0) * 60) })
        expectClean(sim)
    }

    func guardDates(_ sim: MorningSim, day: Int) -> [Date] {
        sim.liveSystem(kind: .guardRing, morning: Std.t(5, 0, day: day)).map(\.date)
    }

    @Test("S22 (A7, D2): during a 3-hour morning the active and next mornings keep all 60 guards within the budget")
    func s22Budget() {
        var sim = MorningSim.armed(Self.threeHours)
        sim.advanceStoppingSnoozes(to: Std.t(6, 0))
        sim.open()
        #expect(guardDates(sim, day: 16).count == 60)
        #expect(guardDates(sim, day: 17).count == 60)
        #expect(sim.system.ids.count <= ScheduleBudget.limit)
        expectClean(sim)
    }

    @Test("S22 (D2): unsolved, every guard keeps coming a minute apart until 08:10; after 08:20 the morning is missed")
    func s22GuardsUntilSolved() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(7, 9, 50))
        sim.lock(cancelUnlock: true)
        for number in 0...60 {
            let ring = number == 0 ? Std.deadline() : Std.guardRing(number)
            sim.advance(to: ring.date.addingTimeInterval(1))
            #expect(sim.alerting.contains(ring.id), "ring \(number) at \(ring.date) alerting")
            sim.press(.stop, on: ring.id)
        }
        sim.advance(to: Std.t(8, 20, 30))
        #expect(sim.alerting.isEmpty)
        sim.open()
        #expect(sim.state.finished[Std.today] == .missed)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("S18 (G4): a time-zone change while suspended rebuilds future mornings at New York's 06:40")
    func s18() {
        var sim = MorningSim.armed()
        sim.changeCalendar(Std.newYork)
        sim.open()
        let mains = (16...18).map { Std.main(of: SimCalendar.date(2026, 11, $0, 6, 40, in: Std.newYork)) }
        #expect(sim.liveSystem(kind: .main) == mains)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        expectClean(sim)
    }

    @Test("S19 (T7): spring forward: an Ideal of 02:30 on 8 March rings at 03:00 or later, no duplicates")
    func s19() {
        let fixture = SimFixture.standard {
            $0.times = WakeTimes(ideal: ClockTime(hour: 2, minute: 30), deadline: ClockTime(hour: 3, minute: 30))
        }
        var sim = MorningSim(fixture: fixture, start: SimCalendar.date(2026, 3, 7, 21, 0))
        sim.launch()
        let mains = sim.liveSystem(kind: .main)
        #expect(mains.count == 3)
        #expect(Std.calendar.component(.hour, from: mains[0].date) == 3)
        #expect(Std.calendar.component(.day, from: mains[0].date) == 8)
        #expect(mains[1].date == SimCalendar.date(2026, 3, 9, 2, 30))
        #expect(Set(sim.liveSystem().map(\.id)).count == sim.liveSystem().count)
        expectClean(sim)
    }

    @Test("S20 (T7): fall back: an Ideal of 01:30 on 1 November uses the first 01:30, 67 distinct rings")
    func s20() {
        let fixture = SimFixture.standard {
            $0.times = WakeTimes(ideal: ClockTime(hour: 1, minute: 30), deadline: ClockTime(hour: 2, minute: 0))
        }
        var sim = MorningSim(fixture: fixture, start: SimCalendar.date(2026, 10, 31, 21, 0))
        sim.launch()
        let ideal = SimCalendar.date(2026, 11, 1, 8, 30, in: SimCalendar.utc)
        let rings = sim.liveSystem(morning: ideal)
        #expect(rings.count == 67)
        #expect(Set(rings.map(\.id)).count == 67)
        #expect(zip(rings, rings.dropFirst()).allSatisfy { $0.date < $1.date })
        expectClean(sim)
    }

    @Test("S21: two settings changes while the first sync is in flight end with only the last settings scheduled")
    func s21() {
        var sim = MorningSim.armed(at: Std.t(12, 0))
        sim.open()
        sim.faults.scheduleLatency = 2
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 50), deadline: ClockTime(hour: 7, minute: 20))
        }
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 7, minute: 0), deadline: ClockTime(hour: 7, minute: 30))
        }
        sim.faults.scheduleLatency = 0
        sim.settle()
        let mains = sim.liveSystem(kind: .main).map(\.date)
        #expect(mains == (17...19).map { Std.t(7, 0, day: $0) })
        #expect(Set(sim.liveSystem().map(\.morning)) == Set((17...19).map { Std.t(7, 0, day: $0) }))
        expectClean(sim)
    }
}

extension Ring {
    /// The same ring moved to another date (its id follows the date).
    func withDate(_ date: Date) -> Ring {
        Ring(date: date, kind: kind, level: level, morning: morning, checkGroup: checkGroup, challenge: challenge)
    }
}
