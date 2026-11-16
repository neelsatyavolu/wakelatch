import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group C, opening, upgrading and solving challenges (contract C1-C7, T5, G1).
@Suite("C: challenge lifecycle")
struct ChallengeLifecycleTests {
    static let kinds = SimFixture.standard {
        $0.snoozeChallenge = .phrase
        $0.deadlineChallenge = .shake
    }

    /// Foreground from 06:39:50 with main alerting at 06:40:05 and its challenge open.
    func challengeAtMain(_ fixture: SimFixture = kinds, snooze: ChallengeKind = .phrase) -> MorningSim {
        var sim = MorningSim.armed(fixture)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main(kind: snooze).id)
        return sim
    }

    @Test("C01 (C1, F2): Start challenge on main opens the snooze kind at level 1, persisted, system alarm silenced")
    func c01() {
        var sim = MorningSim.armed(Self.kinds)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        let main = Std.main(kind: .phrase)
        let effects = sim.tapStartChallenge(main.id)
        let expected = ActiveChallenge(ring: main, kind: .phrase)
        #expect(sim.screen == .challenge(expected))
        #expect(expected.level == 1)
        #expect(effects.first == .persist)
        #expect(silenced(effects) == [main.id])
        #expect(sim.disk.challenge == expected)
        expectClean(sim)
    }

    @Test("C02 (C3): a same-level snooze keeps the challenge; the L2 snooze upgrades it to level 2")
    func c02() {
        var sim = challengeAtMain()
        sim.advance(to: Std.t(6, 49, 5))
        #expect(sim.openChallenge == ActiveChallenge(ring: Std.main(kind: .phrase), kind: .phrase))
        sim.advance(to: Std.t(6, 58, 5))
        #expect(sim.openChallenge == ActiveChallenge(ring: Std.snooze(1, kind: .phrase), kind: .phrase))
        #expect(sim.openChallenge?.level == 2)
        expectClean(sim)
    }

    @Test("C03 (C3, T5): across the deadline the challenge upgrades to level 3 with the deadline kind")
    func c03() {
        var sim = challengeAtMain()
        sim.advance(to: Std.t(7, 10, 5))
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(kind: .shake), kind: .shake)))
        #expect(sim.disk.challenge == ActiveChallenge(ring: Std.deadline(kind: .shake), kind: .shake))
        expectClean(sim)
    }

    @Test("C04 (C3): an upgrade carries a new ring id, so the view's progress resets; no upgrade keeps the id")
    func c04() {
        var sim = challengeAtMain()
        sim.advance(to: Std.t(6, 57, 59))
        let before = sim.openChallenge?.ring.id
        #expect(before == Std.main(kind: .phrase).id)
        sim.advance(to: Std.t(6, 58, 1))
        let after = sim.openChallenge?.ring.id
        #expect(after == Std.snooze(1, kind: .phrase).id)
        #expect(after != before)
        expectClean(sim)
    }

    @Test("C2: Start challenge on an older ring opens the challenge for the latest due ring")
    func olderRingOpensLatest() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 58, 5))
        sim.open()
        sim.tapStartChallenge(Std.main().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.snooze(1), kind: .math)))
        expectClean(sim)
    }

    @Test("C05 (T5, G1): changing the deadline kind mid-morning keeps today's snapshot; tomorrow gets the new kind")
    func c05() {
        var sim = MorningSim.armed(Self.kinds)
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        sim.changeSettings { $0.deadlineChallenge = .steps }
        #expect(Oracle.rings(of: Std.today, in: sim.state.target) == Std.morning(snooze: .phrase, deadline: .shake))
        #expect(sim.ring(.deadline, of: Std.ideal(day: 17))?.challenge == .steps)
        sim.advanceStoppingSnoozes(to: Std.t(7, 10, 5))
        sim.tapStartChallenge(Std.deadline().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(kind: .shake), kind: .shake)))
        expectClean(sim)
    }

    @Test("C06: a kind changed the night before applies to the next morning")
    func c06() {
        var sim = MorningSim.armed()
        sim.open()
        sim.changeSettings { $0.deadlineChallenge = .steps }
        #expect(sim.ring(.deadline, of: Std.today) == Std.deadline(kind: .steps))
        #expect(sim.ring(.guardRing, of: Std.today, index: 59) == Std.guardRing(60, kind: .steps))
        sim.suspend()
        sim.advanceStoppingSnoozes(to: Std.t(7, 10, 5))
        sim.press(.stop, on: Std.deadline(kind: .steps).id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(kind: .steps), kind: .steps)))
        expectClean(sim)
    }

    @Test("C07: a second solved for the same morning is a no-op: one record, one set of awake checks")
    func c07() {
        var sim = challengeAtMain(.standard, snooze: .math)
        sim.advance(to: Std.t(6, 41))
        let first = sim.solve(Std.main().id)
        #expect(scheduled(first).count == 8)
        let second = sim.solve(Std.main().id)
        #expect(second.isEmpty)
        #expect(sim.records.filter { $0.morning == Std.today } == [Std.record(.solved, upAt: Std.t(6, 41))])
        #expect(sim.state.target.filter { $0.kind == .awakeCheck }.count == 8)
        expectClean(sim)
    }

    @Test("C08 (C6, C7): solved naming the pre-upgrade ring is rejected and changes nothing")
    func c08() {
        var sim = challengeAtMain(.standard, snooze: .math)
        sim.advance(to: Std.t(6, 58, 5))
        let effects = sim.solve(Std.main().id)
        #expect(effects.isEmpty)
        #expect(sim.state.finished[Std.today] == nil)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.snooze(1), kind: .math)))
        expectClean(sim)
    }

    @Test("C09 (C6, INV4): a level-1 solve arriving after the L2 ring is due is rejected and the challenge upgrades")
    func c09() {
        var sim = challengeAtMain(.standard, snooze: .math)
        sim.suspend()
        sim.advance(to: Std.t(6, 58, 30))
        let effects = sim.solve(Std.main().id)
        #expect(sim.state.finished[Std.today] == nil)
        #expect(sim.state.challenge == ActiveChallenge(ring: Std.snooze(1), kind: .math))
        #expect(cancelled(effects).isEmpty)
        #expect(scheduled(effects).isEmpty)
        #expect(sim.liveIDs(.guardRing) == ids(Std.guards()))
        expectClean(sim)
    }

    @Test("C10 (C6): an accepted solve cancels every future ring of the morning and schedules the 8 awake checks")
    func c10() {
        var sim = challengeAtMain(.standard, snooze: .math)
        sim.advance(to: Std.t(6, 41))
        let effects = sim.solve(Std.main().id)
        let future = [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] + Std.guards()
        #expect(effects.first == .persist)
        #expect(cancelled(effects) == ids(future))
        #expect(ids(scheduled(effects)) == ids(Std.awakeChecks(solvedAt: Std.t(6, 41))))
        #expect(sim.liveSystem(morning: Std.today) == Std.awakeChecks(solvedAt: Std.t(6, 41)))
        #expect(sim.state.finished[Std.today] == .solved)
        #expect(sim.state.challenge == nil)
        #expect(sim.state.route == nil)
        #expect(sim.screen == .released(Std.record(.solved, upAt: Std.t(6, 41))))
        expectClean(sim)
    }

    @Test("C14 (C5): a challenge survives kill and relaunch, and is upgraded on a later relaunch")
    func c14() {
        var sim = challengeAtMain(.standard, snooze: .math)
        sim.kill()
        sim.advance(to: Std.t(6, 42))
        sim.open()
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        sim.kill()
        sim.advance(to: Std.t(6, 59))
        sim.open()
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.snooze(1), kind: .math)))
        expectClean(sim)
    }

    @Test("L4: records keep the latest 60; a new one drops the oldest")
    func recordLimit() {
        let old = (1...60).map { offset -> MorningRecord in
            let morning = Std.today.addingTimeInterval(-Double(offset) * 86_400 - 3600)
            return MorningRecord(morning: morning, deadline: morning.addingTimeInterval(1800), outcome: .missed, upAt: nil)
        }.reversed()
        var sim = MorningSim.armed(disk: EngineState(records: Array(old)))
        sim.solveToday(at: Std.t(6, 41))
        #expect(sim.records.count == EngineState.recordLimit)
        #expect(sim.records.last == Std.record(.solved, upAt: Std.t(6, 41)))
        #expect(sim.records.first == Array(old)[1])
        expectClean(sim)
    }
}
