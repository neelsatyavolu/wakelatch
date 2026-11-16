import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group C, records, sensor fallback, emergency skip and refused snoozes (contract C4, C6, C8, K1, K2).
@Suite("C: records, fallback, skip, refused snooze")
struct ChallengeEndTests {
    /// Foreground, deadline alerting at 07:10:05 with its challenge open.
    func challengeAtDeadline(_ fixture: SimFixture = .standard, deadline kind: ChallengeKind = .math,
                             disk: EngineState = EngineState(), day: Int = 16, month: Int = 11,
                             start: Date = Std.t(21, 0, day: 15)) -> MorningSim {
        var sim = MorningSim.armed(fixture, at: start, disk: disk)
        let morning = Std.ideal(day: day, month: month)
        sim.advanceStoppingSnoozes(to: morning.addingTimeInterval(1795))
        sim.open()
        sim.advance(to: morning.addingTimeInterval(1805))
        sim.tapStartChallenge(Std.deadline(of: morning, kind: kind).id)
        return sim
    }

    func twoSkipsInNovember() -> EngineState {
        var ledger = SkipLedger()
        _ = ledger.use(at: Std.t(7, 0, day: 2), calendar: Std.calendar)
        _ = ledger.use(at: Std.t(7, 0, day: 9), calendar: Std.calendar)
        return EngineState(skips: ledger)
    }

    @Test("C11 (L4): a solve 30 s after the deadline records the deadline and counts as up by the deadline, not by Ideal")
    func c11() {
        var sim = challengeAtDeadline()
        sim.advance(to: Std.t(7, 10, 30))
        sim.solveOpenChallenge()
        let record = Std.record(.solved, upAt: Std.t(7, 10, 30))
        #expect(sim.records.last == record)
        #expect(record.upByDeadline)
        #expect(!record.upByIdeal)
        expectClean(sim)
    }

    @Test("C11: a solve at 06:44 counts as up by Ideal")
    func upByIdeal() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 44))
        let record = sim.records.last
        #expect(record == Std.record(.solved, upAt: Std.t(6, 44)))
        #expect(record?.upByIdeal == true)
        expectClean(sim)
    }

    @Test("C12 (C4): eyes-open unavailable falls back to math at the same ring and level, and math then solves")
    func c12() {
        var sim = MorningSim.armed(.standard { $0.snoozeChallenge = .eyesOpen })
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        let main = Std.main(kind: .eyesOpen)
        sim.tapStartChallenge(main.id)
        #expect(sim.openChallenge == ActiveChallenge(ring: main, kind: .eyesOpen))
        sim.challengeUnavailable(.eyesOpen)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: main, kind: .math)))
        #expect(sim.disk.challenge == ActiveChallenge(ring: main, kind: .math))
        sim.solve(main.id)
        #expect(sim.state.finished[Std.today] == .solved)
        expectClean(sim)
    }

    @Test("C13 (C4): steps unavailable at the deadline falls back to math at L3; another kind's failure changes nothing")
    func c13() {
        var sim = challengeAtDeadline(.standard { $0.deadlineChallenge = .steps }, deadline: .steps)
        let deadline = Std.deadline(kind: .steps)
        #expect(sim.openChallenge == ActiveChallenge(ring: deadline, kind: .steps))
        let unrelated = sim.challengeUnavailable(.shake)
        #expect(unrelated.isEmpty)
        #expect(sim.openChallenge == ActiveChallenge(ring: deadline, kind: .steps))
        sim.challengeUnavailable(.steps)
        #expect(sim.openChallenge == ActiveChallenge(ring: deadline, kind: .math))
        #expect(sim.openChallenge?.level == 3)
        sim.solve(deadline.id)
        #expect(sim.state.finished[Std.today] == .solved)
        expectClean(sim)
    }

    @Test("C15 (K1): skip ends the morning: skipped record, every future ring cancelled, no awake checks, home")
    func c15() {
        var sim = challengeAtDeadline()
        sim.advance(to: Std.t(7, 10, 10))
        let effects = sim.skip(Std.deadline().id)
        #expect(effects.first == .persist)
        #expect(sim.state.finished[Std.today] == .skipped)
        #expect(sim.records.last == Std.record(.skipped))
        #expect(cancelled(effects) == ids(Std.guards()))
        #expect(scheduled(effects).isEmpty)
        #expect(sim.screen == .none)
        #expect(sim.state.challenge == nil)
        #expect(sim.engine?.skipsLeft(at: sim.now) == 1)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        expectClean(sim)
    }

    @Test("C16 (K2): a third skip in the same month is refused and the morning continues")
    func c16() {
        var sim = challengeAtDeadline(disk: twoSkipsInNovember())
        let before = sim.state
        sim.skip(Std.deadline().id)
        #expect(sim.state.finished[Std.today] == nil)
        #expect(sim.state.skips == before.skips)
        #expect(sim.engine?.skipsLeft(at: sim.now) == 0)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(), kind: .math)))
        #expect(sim.liveIDs(.guardRing) == ids(Std.guards()))
        expectClean(sim)
    }

    @Test("C17 (K2): skips reset on the first of the month: refused on 30 November, accepted on 1 December")
    func c17() {
        var sim = challengeAtDeadline(disk: twoSkipsInNovember(), day: 30, start: Std.t(21, 0, day: 29))
        let november = Std.ideal(day: 30)
        sim.skip(Std.deadline(of: november).id)
        #expect(sim.state.finished[november] == nil)
        sim.suspend()
        let december = Std.ideal(day: 1, month: 12)
        sim.advanceStoppingSnoozes(to: december.addingTimeInterval(1795))
        sim.open()
        sim.advance(to: december.addingTimeInterval(1805))
        #expect(sim.state.finished[november] == .missed)
        sim.tapStartChallenge(Std.deadline(of: december).id)
        sim.skip(Std.deadline(of: december).id)
        #expect(sim.state.finished[december] == .skipped)
        #expect(sim.engine?.skipsLeft(at: sim.now) == 1)
        expectClean(sim)
    }

    @Test("C18 (C8): Snooze on the deadline or a guard is refused and changes nothing", arguments: [0, 1])
    func c18(guardNumber: Int) {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(7, 9, 50))
        sim.open()
        let ring = guardNumber == 0 ? Std.deadline() : Std.guardRing(guardNumber)
        sim.advance(to: ring.date.addingTimeInterval(5))
        let screen = sim.screen
        let state = sim.state
        let effects = sim.tapSnooze(ring.id)
        #expect(effects.isEmpty)
        #expect(sim.screen == screen)
        #expect(sim.state == state)
        #expect(sim.engine?.session.dismissedThisVisit == nil)
        expectClean(sim)
    }
}
