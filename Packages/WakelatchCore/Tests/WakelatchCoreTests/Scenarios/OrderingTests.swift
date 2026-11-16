import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group X: concurrency and ordering. Late system-table reads, overlapping reconciles, late alerting events.
@Suite("X: ordering and late results")
struct OrderingTests {
    /// Foreground with main's challenge open at 06:40:05, schedules taking `latency` steps to land.
    func challengeOpen(latency: Int = 0) -> MorningSim {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        sim.faults.scheduleLatency = latency
        return sim
    }

    func latchedAlerting(_ sim: MorningSim) -> Set<UUID> {
        sim.alerting.intersection(ids(Std.latched()))
    }

    func isRinging(_ screen: Screen) -> Bool {
        if case .ringing = screen { return true }
        return false
    }

    @Test("X01: a solve between a table read and its delivery never revives the morning; nothing latched rings later")
    func x01() {
        var sim = challengeOpen(latency: 3)
        sim.advance(to: Std.t(6, 41))
        let stale = sim.system.snapshot
        sim.solve(Std.main().id)
        sim.send(.systemTable(stale, now: sim.now))
        sim.faults.scheduleLatency = 0
        sim.settle()
        sim.advance(to: Std.t(6, 49, 10))
        #expect(sim.state.finished[Std.today] == .solved)
        #expect(sim.state.target.filter { $0.morning == Std.today }.allSatisfy { $0.kind == .awakeCheck })
        #expect(latchedAlerting(sim).isEmpty)
        #expect(!isRinging(sim.screen))
        expectClean(sim)
    }

    @Test("X02: a skip between a table read and its delivery never revives the morning")
    func x02() {
        var sim = challengeOpen(latency: 3)
        sim.advance(to: Std.t(6, 41))
        let stale = sim.system.snapshot
        sim.skip(Std.main().id)
        sim.send(.systemTable(stale, now: sim.now))
        sim.faults.scheduleLatency = 0
        sim.settle()
        sim.advance(to: Std.t(6, 49, 10))
        #expect(sim.state.finished[Std.today] == .skipped)
        #expect(sim.state.target.filter { $0.morning == Std.today }.isEmpty)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("X03: a confirmed check group stays cancelled when an older table read arrives afterwards")
    func x03() {
        var sim = challengeOpen()
        sim.advance(to: Std.t(6, 41))
        sim.solve(Std.main().id)
        sim.closeReleased()
        sim.advance(to: Std.t(6, 46, 10))
        let group = Std.awakeGroup(0, solvedAt: Std.t(6, 41))
        let stale = sim.system.snapshot
        sim.tapImUp(group[0].id)
        sim.send(.systemTable(stale, now: sim.now))
        sim.settle()
        #expect(ids(group).isDisjoint(with: sim.system.ids))
        #expect(ids(group).isDisjoint(with: ids(sim.state.target)))
        sim.advance(to: Std.t(6, 49, 10))
        #expect(sim.alerting.isDisjoint(with: ids(group)))
        expectClean(sim)
    }

    @Test("X04: a tick between launched and the intent's alertAction plays no chime when the pressed ring was the only one")
    func x04() {
        var sim = MorningSim.armed(order: .afterFirstTick)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.kill()
        sim.advance(to: Std.t(6, 40, 10))
        let mark = sim.effectLog.count
        sim.press(.secondary, on: Std.main().id)
        #expect(!playsChime(sim.effects(since: mark)))
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        expectClean(sim)
    }

    @Test("X05: two table reads while the first pass is in flight schedule nothing twice")
    func x05() {
        var sim = MorningSim(start: Std.t(21, 0, day: 15), faults: SimFaults(scheduleLatency: 5))
        sim.launch()
        #expect(!sim.inFlight.isEmpty)
        let first = sim.send(.systemTable(sim.system.snapshot, now: sim.now))
        let second = sim.send(.systemTable(sim.system.snapshot, now: sim.now))
        #expect(scheduled(first).isEmpty)
        #expect(scheduled(second).isEmpty)
        #expect(cancelled(first + second).isEmpty)
        sim.faults.scheduleLatency = 0
        sim.settle()
        let expected = Std.morning() + Std.morning(Std.ideal(day: 17)) + Std.morning(Std.ideal(day: 18))
        #expect(sim.system.ids == ids(expected))
        let schedules = sim.system.log.compactMap { op -> UUID? in
            if case .schedule(let id) = op { return id }
            return nil
        }
        #expect(schedules.count == expected.count)
        expectClean(sim)
    }

    @Test("X06: an alerting event naming the solved morning's rings, arriving after the solve, does not reshow them")
    func x06() {
        var sim = challengeOpen()
        sim.advance(to: Std.t(6, 41))
        sim.solve(Std.main().id)
        let released = Screen.released(Std.record(.solved, upAt: Std.t(6, 41)))
        #expect(sim.screen == released)
        let mark = sim.effectLog.count
        sim.send(.alerting([Std.main().id, Std.snooze(0).id], now: sim.now, audible: true, coverVisible: true))
        #expect(sim.screen == released)
        #expect(!playsChime(sim.effects(since: mark)))
        expectClean(sim)
    }
}
