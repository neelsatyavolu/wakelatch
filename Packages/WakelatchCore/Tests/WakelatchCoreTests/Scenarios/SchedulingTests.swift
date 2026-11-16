import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group S, S01-S11: arming, settings changes during a morning (D3), one-off alarms, reconcile order.
@Suite("S: scheduling and settings changes")
struct SchedulingTests {
    let tomorrow = Std.ideal(day: 17)

    func times(_ ideal: (Int, Int), _ deadline: (Int, Int)) -> WakeTimes {
        WakeTimes(ideal: ClockTime(hour: ideal.0, minute: ideal.1), deadline: ClockTime(hour: deadline.0, minute: deadline.1))
    }

    func mornings(in sim: MorningSim) -> Set<Date> {
        Set(sim.state.target.filter { $0.kind != .awakeCheck }.map(\.morning))
    }

    @Test("S01 (A1, R3): launched at 06:30 with nudges on, today is armed; only its future rings are scheduled")
    func s01() {
        var sim = MorningSim(start: Std.t(6, 30))
        sim.launch()
        #expect(sim.liveIDs(morning: Std.today) == ids(Std.latched()))
        #expect(sim.liveSystem(kind: .nudge, morning: Std.today).isEmpty)
        #expect(sim.system.contains(Std.main(of: tomorrow).id))
        expectClean(sim)
    }

    @Test("S02 (A1): launched at 06:40:00, today is not armed; tomorrow is next")
    func s02() {
        var sim = MorningSim(start: Std.t(6, 40))
        sim.launch()
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        #expect(!mornings(in: sim).contains(Std.today))
        #expect(sim.liveSystem(kind: .main).first == Std.main(of: tomorrow))
        expectClean(sim)
    }

    @Test("S03: turning nudges on at 06:28 (no nudges before, not under way) adds only today's future nudge")
    func s03() {
        var sim = MorningSim.armed(.noNudges)
        sim.advance(to: Std.t(6, 28))
        sim.open()
        sim.changeSettings { $0.timing = .production(PlanOptions(nudges: true)) }
        #expect(sim.liveSystem(kind: .nudge, morning: Std.today) == [Std.nudge(1)])
        #expect(sim.liveIDs(morning: Std.today).subtracting([Std.nudge(1).id]) == ids(Std.latched()))
        #expect(sim.system.contains(Std.nudge(0, of: tomorrow).id))
        expectClean(sim)
    }

    @Test("S04 (D3): moving Ideal to 06:35 at 06:30 while today is under way keeps today's chain; tomorrow moves")
    func s04UnderWay() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 30, 5))
        sim.open()
        sim.changeSettings { $0.times = times((6, 35), (7, 5)) }
        #expect(ids(Std.latched()).isSubset(of: sim.liveIDs(morning: Std.today)))
        #expect(!mornings(in: sim).contains(Std.t(6, 35)))
        #expect(sim.system.contains(Std.main(of: Std.t(6, 35, day: 17)).id))
        #expect(sim.engine?.underWay(at: sim.now)?.morning == Std.today)
        expectClean(sim)
    }

    @Test("S04: moving Ideal to 06:35 at 06:30 with no nudges (nothing has rung) moves today's morning")
    func s04NotStarted() {
        var sim = MorningSim.armed(.noNudges)
        sim.advance(to: Std.t(6, 30))
        sim.open()
        sim.changeSettings { $0.times = times((6, 35), (7, 5)) }
        #expect(sim.system.contains(Std.main(of: Std.t(6, 35)).id))
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        expectClean(sim)
    }

    @Test("S05 (D3, A2, G3): moving Ideal to 07:30 at 06:45 creates no second morning today; today's chain is intact")
    func s05() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        sim.changeSettings { $0.times = times((7, 30), (8, 0)) }
        let future = [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] + Std.guards()
        #expect(ids(future).isSubset(of: sim.system.ids))
        #expect(!mornings(in: sim).contains(Std.t(7, 30)))
        #expect(sim.system.contains(Std.main(of: Std.t(7, 30, day: 17)).id))
        #expect(sim.engine?.underWay(at: sim.now) == UnderWay(morning: Std.today, deadline: Std.t(7, 10), endsBy: Std.t(8, 20)))
        expectClean(sim)
    }

    @Test("S06 (D3, G2): turning the alarm off at 06:45 removes later mornings only; today stays under way")
    func s06() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        sim.changeSettings { $0.enabled = false }
        #expect(sim.liveSystem(morning: tomorrow).isEmpty)
        #expect(sim.liveSystem(morning: Std.ideal(day: 18)).isEmpty)
        #expect(ids(Std.guards()).isSubset(of: sim.system.ids))
        #expect(sim.engine?.underWay(at: sim.now) == UnderWay(morning: Std.today, deadline: Std.t(7, 10), endsBy: Std.t(8, 20)))
        sim.tapStartChallenge(Std.main().id)
        sim.solveOpenChallenge()
        #expect(sim.engine?.nextMorning(at: sim.now) == nil)
        #expect(sim.liveSystem().allSatisfy { $0.kind == .awakeCheck })
        expectClean(sim)
    }

    enum OneOffEnd: String, CaseIterable, Sendable { case solved, skipped, missed }

    @Test("S07 (A4): a one-off morning that ends in any way turns the alarm off and arms nothing else",
          arguments: OneOffEnd.allCases)
    func s07(end: OneOffEnd) {
        var sim = MorningSim.armed(.standard { $0.repeatDays = [] })
        #expect(sim.state.oneOffMorning == Std.today)
        #expect(mornings(in: sim) == [Std.today])
        switch end {
        case .solved:
            sim.solveToday(at: Std.t(6, 41))
        case .skipped:
            sim.advanceStoppingSnoozes(to: Std.t(7, 9, 55))
            sim.open()
            sim.advance(to: Std.t(7, 10, 5))
            sim.tapStartChallenge(Std.deadline().id)
            sim.skip(Std.deadline().id)
        case .missed:
            sim.advance(to: Std.t(8, 21))
            sim.open()
        }
        #expect(sim.effectLog.contains(.disableAlarm))
        #expect(sim.settings.enabled == false)
        #expect(sim.engine?.settings.enabled == false)
        sim.suspend()
        sim.advance(to: Std.t(22, 0))
        sim.open()
        #expect(sim.liveSystem().allSatisfy { $0.morning == Std.today && $0.kind == .awakeCheck })
        #expect(!mornings(in: sim).contains(tomorrow))
        expectClean(sim)
    }

    @Test("S08 (A4): while a one-off morning is under way no next day is armed, even after a settings change")
    func s08() {
        var sim = MorningSim.armed(.standard { $0.repeatDays = [] })
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        #expect(Set(sim.liveSystem().map(\.morning)) == [Std.today])
        sim.changeSettings { $0.awakeChecks = false }
        #expect(Set(sim.liveSystem().map(\.morning)) == [Std.today])
        #expect(mornings(in: sim) == [Std.today])
        expectClean(sim)
    }

    @Test("S09 (R6, I2): a resync with nothing changed emits nothing; a relaunch schedules and cancels nothing")
    func s09() {
        var sim = MorningSim.armed()
        sim.open()
        #expect(sim.send(.systemTable(sim.system.snapshot, now: sim.now)).isEmpty)
        let mark = sim.system.log.count
        sim.kill()
        sim.advance(by: 60)
        sim.open()
        #expect(sim.system.log.count == mark)
        expectClean(sim)
    }

    @Test("S10, S11 (R2): an empty AlarmKit at 06:45 is refilled deadline and guards first, cancels next, other mornings last")
    func s10s11() throws {
        let disk = MorningSim.armed().disk
        var sim = MorningSim(start: Std.t(6, 45), disk: disk)
        let orphan = Std.guardRing(4, of: Std.ideal(day: 12))
        sim.plant(orphan)
        sim.launch()
        let schedules = sim.system.log.compactMap { op -> UUID? in
            if case .schedule(let id) = op { return id }
            return nil
        }
        let first = [Std.deadline()] + Std.guards() + [Std.snooze(0), Std.snooze(1), Std.snooze(2)]
        #expect(Array(schedules.prefix(first.count)) == first.map(\.id))
        let cancelIndex = try #require(sim.system.log.firstIndex(of: .cancel(orphan.id)))
        let scheduleOps = sim.system.log.enumerated().compactMap { index, op -> (index: Int, id: UUID)? in
            if case .schedule(let id) = op { return (index, id) }
            return nil
        }
        let today = ids(first)
        #expect(scheduleOps.filter { today.contains($0.id) }.allSatisfy { $0.index < cancelIndex })
        #expect(scheduleOps.filter { !today.contains($0.id) }.allSatisfy { $0.index > cancelIndex })
        #expect(scheduleOps.contains { !today.contains($0.id) })
        expectClean(sim)
    }
}
