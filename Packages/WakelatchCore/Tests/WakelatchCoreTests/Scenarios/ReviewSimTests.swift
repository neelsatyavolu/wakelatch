import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Regressions for review findings that need whole processes: kills, stale tables and late AlarmKit calls.
@Suite("Review: sim regressions")
struct ReviewSimTests {
    @Test("Review 1 end to end: shorten the window, killed before the cancels; after the Deadline only L3 opens")
    func shortenWindowThenKill() throws {
        let long = SimFixture.standard {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 9, minute: 30))
            $0.timing = .production(PlanOptions(snoozeMinutes: 3))
        }
        var sim = MorningSim(fixture: long, start: Std.t(21, 0, day: 15))
        sim.launch()
        sim.settle()
        sim.killAfter(effects: 3)
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
            $0.timing = .production(PlanOptions())
        }
        try #require(sim.engine == nil)
        let stale = sim.liveSystem(kind: .snooze, morning: Std.today).filter { $0.date > Std.t(7, 10) }
        try #require(!stale.isEmpty, "old snoozes after the new Deadline are still in AlarmKit")
        sim.advance(to: Std.t(7, 11, 5))
        sim.open()
        sim.settle()
        #expect(ids(stale).isDisjoint(with: sim.system.ids), "never adopted, so cancelled")
        sim.advance(to: Std.t(7, 15, 30))
        let staleDue = try #require(stale.first { $0.date <= Std.t(7, 15, 30) })
        sim.tapStartChallenge(staleDue.id)
        #expect(sim.openChallenge?.level == 3)
        sim.solve(staleDue.id)
        #expect(sim.state.finished[Std.today] == nil)
        expectClean(sim)
    }

    @Test("Review 14 (R1, R5): a cancel sent before a kill lands after the next launch's read; the next read repairs it")
    func lateCancelAfterRelaunch() {
        var sim = MorningSim.armed()
        sim.open()
        sim.faults.cancelLatency = 2
        sim.faults.inFlightSurvivesKill = true
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 50), deadline: ClockTime(hour: 7, minute: 20))
        }
        sim.kill()
        sim.faults = SimFaults()
        // The settings save died with the process: the next launch has the 06:40 settings again.
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
        }
        sim.open()
        let expected = Std.morning() + Std.morning(Std.ideal(day: 17)) + Std.morning(Std.ideal(day: 18))
        #expect(!ids(expected).isSubset(of: sim.system.ids), "the late cancel removed a wanted ring")
        sim.advance(by: 10)
        sim.settle()
        #expect(ids(expected) == sim.system.ids)
        expectClean(sim)
    }

    @Test("Review 14: a schedule sent before a kill lands late and the extra alarm is cancelled on the next read")
    func lateScheduleAfterRelaunch() {
        var sim = MorningSim.armed()
        sim.open()
        sim.faults.scheduleLatency = 2
        sim.faults.inFlightSurvivesKill = true
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 50), deadline: ClockTime(hour: 7, minute: 20))
        }
        sim.kill()
        sim.faults = SimFaults()
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
        }
        sim.open()
        sim.advance(by: 10)
        sim.settle()
        let expected = Std.morning() + Std.morning(Std.ideal(day: 17)) + Std.morning(Std.ideal(day: 18))
        #expect(ids(expected) == sim.system.ids)
        expectClean(sim)
    }

    @Test("Review 17: a full morning reaches settled passes, so INV5, INV7 and INV8 really run")
    func settledPassesHappen() {
        var sim = MorningSim.armed()
        sim.solveToday()
        sim.advance(by: 30)
        #expect(sim.checker.settledSteps > 0)
        expectClean(sim)
    }
}
