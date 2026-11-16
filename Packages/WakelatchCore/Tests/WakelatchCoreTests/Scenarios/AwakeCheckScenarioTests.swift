import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group A: awake checks after a solve (contract W1-W5, C6.3, INV5).
@Suite("A: awake checks")
struct AwakeCheckScenarioTests {
    let solvedAt = Std.t(6, 41)
    var group0: [Ring] { Std.awakeGroup(0, solvedAt: solvedAt) }
    var group1: [Ring] { Std.awakeGroup(1, solvedAt: solvedAt) }

    /// Foreground with main's challenge open at 06:40:05.
    func challengeOpen(_ fixture: SimFixture = .standard) -> MorningSim {
        var sim = MorningSim.armed(fixture)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        return sim
    }

    @Test("A01 (W1): a solve at 06:41 holds checks at 06:46 and 06:53, each with 3 guards a minute apart")
    func a01() {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        #expect(sim.liveSystem(kind: .awakeCheck, morning: Std.today) == group0 + group1)
        #expect(sim.liveSystem(morning: Std.today).allSatisfy { $0.kind == .awakeCheck })
        #expect(sim.engine?.pendingAwakeChecks(at: sim.now) == [Std.t(6, 46), Std.t(6, 53)])
        expectClean(sim)
    }

    @Test("A02: a solve while a reconcile's schedules are still in flight keeps every awake check")
    func a02() {
        var sim = challengeOpen()
        sim.faults.scheduleLatency = 2
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 6, minute: 45), deadline: ClockTime(hour: 7, minute: 15))
        }
        #expect(!sim.inFlight.isEmpty)
        sim.advance(to: solvedAt)
        sim.solve(Std.main().id)
        sim.faults.scheduleLatency = 0
        sim.settle()
        #expect(sim.liveSystem(morning: Std.today) == group0 + group1)
        #expect(sim.system.contains(Std.main(of: Std.t(6, 45, day: 17)).id))
        #expect(!sim.system.contains(Std.main(of: Std.ideal(day: 17)).id))
        expectClean(sim)
    }

    @Test("A03: a system table read before the solve and delivered after it does not drop the checks")
    func a03() {
        var sim = challengeOpen()
        sim.advance(to: solvedAt)
        let stale = sim.system.snapshot
        sim.solve(Std.main().id)
        sim.send(.systemTable(stale, now: sim.now))
        sim.settle()
        #expect(sim.liveSystem(morning: Std.today) == group0 + group1)
        #expect(sim.state.target.filter { $0.morning == Std.today } .count == 8)
        expectClean(sim)
    }

    @Test("A04 (W1): with awake checks off, a solve schedules nothing and leaves nothing for the morning")
    func a04() {
        var sim = challengeOpen(.standard { $0.awakeChecks = false })
        sim.advance(to: solvedAt)
        let effects = sim.solve(Std.main().id)
        #expect(scheduled(effects).isEmpty)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        #expect(sim.engine?.pendingAwakeChecks(at: sim.now) == [])
        #expect(sim.screen == .released(Std.record(.solved, upAt: solvedAt)))
        expectClean(sim)
    }

    @Test("A05 (W5): opening from a due check keeps the check on screen and its group in AlarmKit, warm and cold",
          arguments: [false, true])
    func a05(cold: Bool) {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        sim.suspend()
        if cold { sim.kill() }
        sim.advance(to: Std.t(6, 46, 10))
        sim.open()
        #expect(sim.screen == .awakeCheck(group0[0]))
        #expect(ids(Array(group0.dropFirst()) + group1).isSubset(of: sim.system.ids))
        sim.advance(by: 10)
        #expect(sim.screen == .awakeCheck(group0[0]))
        expectClean(sim)
    }

    @Test("A06 (W3): in-app 'I'm up' cancels its group; the other group is untouched")
    func a06() {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        sim.closeReleased()
        sim.advance(to: Std.t(6, 46, 10))
        let effects = sim.tapImUp(group0[0].id)
        #expect(cancelled(effects) == ids(group0))
        #expect(ids(group0).isSubset(of: sim.state.acknowledged))
        #expect(sim.liveSystem(kind: .awakeCheck) == group1)
        expectClean(sim)
    }

    @Test("A07 (W4, S3): an ignored check's guards ring, then expire 15 minutes after each ring")
    func a07() {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        sim.suspend()
        sim.advance(to: Std.t(6, 49, 10))
        #expect(ids(group0).isSubset(of: sim.alerting))
        sim.advance(to: Std.t(7, 5))
        sim.open()
        #expect(ids(group0).isDisjoint(with: ids(sim.state.target)))
        #expect(ids(group0).isDisjoint(with: sim.system.ids))
        #expect(sim.screen == .awakeCheck(group1[3]))
        sim.advance(to: Std.t(7, 12))
        #expect(sim.screen == .none)
        #expect(sim.state.target.filter { $0.morning == Std.today }.isEmpty)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        expectClean(sim)
    }

    @Test("A08: confirming the first check leaves the second to ring at 06:53")
    func a08() {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        sim.suspend()
        sim.advance(to: Std.t(6, 46, 10))
        sim.press(.secondary, on: group0[0].id)
        sim.advance(to: Std.t(6, 53, 1))
        #expect(sim.alerting.contains(group1[0].id))
        #expect(sim.alerting.isDisjoint(with: ids(group0)))
        expectClean(sim)
    }

    @Test("A09 (L1): due awake checks never make the solved morning active again")
    func a09() {
        var sim = MorningSim.armed()
        sim.solveToday(at: solvedAt)
        sim.suspend()
        sim.advance(to: Std.t(6, 46, 10))
        sim.open()
        #expect(sim.engine?.activeMorning(at: sim.now) == nil)
        #expect(sim.engine?.underWay(at: sim.now) == nil)
        #expect(sim.state.finished[Std.today] == .solved)
        #expect(sim.screen == .awakeCheck(group0[0]))
        expectClean(sim)
    }
}
