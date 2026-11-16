import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group R, named cases R01-R09 (contract B3, S1, C1, C3).
@Suite("R: alert buttons, named cases 1-9")
struct AlertButtonNamedTests {
    /// Monday at 06:40:10: nudges were stopped from the lock screen, main is alerting.
    func mainAlerting(killed: Bool, fixture: SimFixture = .standard, order: IntentOrder = .afterActive) -> MorningSim {
        var sim = MorningSim.armed(fixture, order: order)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        if killed { sim.kill() }
        sim.advance(to: Std.t(6, 40, 10))
        return sim
    }

    func expectRestOfMorningLive(_ sim: MorningSim, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(sim.liveIDs(.snooze) == ids([Std.snooze(0), Std.snooze(1), Std.snooze(2)]), sourceLocation: sourceLocation)
        #expect(sim.liveIDs(.deadline) == [Std.deadline().id], sourceLocation: sourceLocation)
        #expect(sim.liveIDs(.guardRing) == ids(Std.guards()), sourceLocation: sourceLocation)
    }

    @Test("R01: main 'I'm up' on a killed app lands on the L1 challenge, with no chime and the rest of the morning live")
    func r01() {
        var sim = mainAlerting(killed: true)
        let mark = sim.effectLog.count
        #expect(sim.press(.secondary, on: Std.main().id) == .openToChallenge)
        #expect(sim.process == .foreground(.home))
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        #expect(sim.openChallenge?.level == 1)
        #expect(sim.sound == .silent)
        #expect(!playsChime(sim.effects(since: mark)))
        #expect(sim.disk.challenge == ActiveChallenge(ring: Std.main(), kind: .math))
        expectRestOfMorningLive(sim)
        expectClean(sim)
    }

    @Test("R02: main 'I'm up' on a suspended app gives exactly the cold result (screen, sound, challenge)")
    func r02() {
        var cold = mainAlerting(killed: true)
        var warm = mainAlerting(killed: false)
        cold.press(.secondary, on: Std.main().id)
        warm.press(.secondary, on: Std.main().id)
        #expect(warm.screen == cold.screen)
        #expect(warm.sound == cold.sound)
        #expect(warm.state.challenge == cold.state.challenge)
        #expect(warm.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        expectRestOfMorningLive(warm)
        expectClean(cold)
        expectClean(warm)
    }

    @Test("R03: 'I'm up' 100 s after main started still opens the challenge (no timing heuristic)")
    func r03() {
        var sim = mainAlerting(killed: false)
        sim.advance(to: Std.t(6, 41, 40))
        sim.press(.secondary, on: Std.main().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        expectClean(sim)
    }

    @Test("R04: 'I'm up' on the second snooze (L2) opens the L2 challenge for that ring")
    func r04() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 57, 30))
        sim.advance(to: Std.t(6, 58, 10))
        sim.press(.secondary, on: Std.snooze(1).id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.snooze(1), kind: .math)))
        #expect(sim.openChallenge?.level == 2)
        #expect(sim.system.contains(Std.snooze(2).id))
        expectClean(sim)
    }

    @Test("R05: deadline Stop on a killed app opens the L3 challenge with the deadline's snapshotted kind")
    func r05() {
        let fixture = SimFixture.standard {
            $0.snoozeChallenge = .phrase
            $0.deadlineChallenge = .shake
        }
        var sim = MorningSim.armed(fixture)
        sim.advanceStoppingSnoozes(to: Std.t(7, 9, 30))
        sim.kill()
        sim.advance(to: Std.t(7, 10, 10))
        let deadline = Std.deadline(kind: .shake)
        #expect(sim.press(.stop, on: deadline.id) == .openToChallenge)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: deadline, kind: .shake)))
        #expect(sim.openChallenge?.level == 3)
        #expect(sim.system.contains(Std.guardRing(1, kind: .shake).id))
        expectClean(sim)
    }

    @Test("R06: deadline 'Solve' with a stale L1 challenge in memory upgrades to the deadline's L3 challenge")
    func r06() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        #expect(sim.openChallenge == ActiveChallenge(ring: Std.main(), kind: .math))
        sim.suspend()
        sim.advance(to: Std.t(7, 10, 10))
        sim.press(.secondary, on: Std.deadline().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(), kind: .math)))
        #expect(sim.openChallenge?.ring.id != Std.main().id)
        expectClean(sim)
    }

    @Test("R07: Stop on an older guard at 07:17 routes to the latest due guard (guard 7), not the pressed one")
    func r07() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(7, 9, 30))
        sim.kill()
        sim.advance(to: Std.t(7, 17, 10))
        #expect(sim.alerting.contains(Std.guardRing(3).id))
        sim.press(.stop, on: Std.guardRing(3).id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.guardRing(7), kind: .math)))
        #expect(sim.system.contains(Std.guardRing(8).id))
        expectClean(sim)
    }

    @Test("R08: guard Stop with yesterday's challenge still in memory opens today's guard challenge; yesterday is missed")
    func r08() {
        let sunday = Std.ideal(day: 15)
        var sim = MorningSim.armed(at: Std.t(6, 0, day: 15))
        sim.advance(to: Std.t(6, 40, 5, day: 15))
        sim.open()
        sim.tapStartChallenge(Std.main(of: sunday).id)
        sim.suspend()
        sim.advance(to: Std.t(7, 12, 10))
        sim.press(.stop, on: Std.guardRing(2).id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.guardRing(2), kind: .math)))
        #expect(sim.state.finished[sunday] == .missed)
        #expect(sim.records.contains(Std.record(.missed, of: sunday)))
        #expect(sim.liveSystem(morning: sunday).isEmpty)
        expectClean(sim)
    }

    @Test("R09: deadline Stop after yesterday's Released was left up and the phone locked opens today's deadline challenge")
    func r09() {
        let sunday = Std.ideal(day: 15)
        var sim = MorningSim.armed(at: Std.t(6, 0, day: 15))
        sim.solveToday(at: Std.t(6, 41, day: 15), morning: sunday)
        #expect(sim.screen == .released(Std.record(.solved, of: sunday, upAt: Std.t(6, 41, day: 15))))
        sim.lock(cancelUnlock: false)
        sim.advanceStoppingSnoozes(to: Std.t(7, 10, 10))
        let stepMark = sim.steps.count
        sim.press(.stop, on: Std.deadline().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(), kind: .math)))
        #expect(!sim.screens(since: stepMark).contains { if case .released = $0 { true } else { false } })
        #expect(sim.records.contains(Std.record(.solved, of: sunday, upAt: Std.t(6, 41, day: 15))))
        expectClean(sim)
    }
}
