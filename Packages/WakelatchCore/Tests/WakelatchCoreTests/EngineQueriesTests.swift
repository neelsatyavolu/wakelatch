import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract L1, L5 and the engine's pure queries, on hand-built state (the old MorningUnderWay tests ported).
@Suite("L: engine queries on a given state")
struct EngineQueriesTests {
    let tomorrow = Std.ideal(day: 17)

    func engine(_ state: EngineState, _ change: (inout EngineSettings) -> Void = { _ in }) -> MorningEngine {
        var settings = SimFixture.standard.settings
        change(&settings)
        return MorningEngine(state: state, settings: settings, calendar: Std.calendar)
    }

    var armed: EngineState { EngineState(target: Std.morning() + Std.morning(tomorrow)) }

    @Test("L1: before the first nudge nothing is active")
    func beforeFirstRing() {
        #expect(engine(armed).activeMorning(at: Std.t(6, 19, 59)) == nil)
    }

    @Test("L1: once a nudge is due the morning is active, so its later rings are kept")
    func activeFromNudge() {
        let e = engine(armed)
        #expect(e.activeMorning(at: Std.t(6, 20)) == Std.today)
        #expect(e.activeMorning(at: Std.t(6, 39)) == Std.today)
        #expect(e.activeMorning(at: Std.t(6, 55)) == Std.today)
    }

    @Test("L1: active until the last guard plus grace (08:20), then not")
    func endsAfterGrace() {
        let e = engine(armed)
        #expect(e.activeMorning(at: Std.t(8, 20)) == Std.today)
        #expect(e.activeMorning(at: Std.t(8, 20, 1)) == nil)
    }

    @Test("L1: a finished morning is never active")
    func finishedNotActive() {
        var state = armed
        state.finished[Std.today] = .skipped
        #expect(engine(state).activeMorning(at: Std.t(6, 50)) == nil)
    }

    @Test("L1: when two mornings qualify the oldest is active")
    func oldestWins() {
        let second = Std.t(6, 50)
        let state = EngineState(target: Std.morning() + Std.morning(second))
        #expect(engine(state).activeMorning(at: Std.t(7, 0)) == Std.today)
    }

    @Test("L1 (A09): awake checks never make a morning active")
    func awakeChecksNotActive() {
        var state = EngineState(target: Std.awakeChecks(solvedAt: Std.t(6, 41)))
        state.finished[Std.today] = .solved
        #expect(engine(state).activeMorning(at: Std.t(6, 47)) == nil)
        let unfinished = EngineState(target: Std.awakeChecks(solvedAt: Std.t(6, 41)))
        #expect(engine(unfinished).activeMorning(at: Std.t(6, 47)) == nil)
    }

    @Test("L5: underWay reports the active morning, its deadline and endsBy; nil when nothing is active")
    func underWay() {
        let e = engine(armed)
        #expect(e.underWay(at: Std.t(6, 45)) == UnderWay(morning: Std.today, deadline: Std.t(7, 10), endsBy: Std.t(8, 20)))
        #expect(e.underWay(at: Std.t(6, 0)) == nil)
        #expect(e.underWay(at: Std.t(9, 0)) == nil)
    }

    @Test("latest due latched ring: the latest main, snooze, deadline or guard at or before now; nudges never count")
    func latestDue() {
        let e = engine(armed)
        #expect(e.latestDueLatched(of: Std.today, at: Std.t(6, 35)) == nil)
        #expect(e.latestDueLatched(of: Std.today, at: Std.t(6, 40)) == Std.main())
        #expect(e.latestDueLatched(of: Std.today, at: Std.t(6, 58, 30)) == Std.snooze(1))
        #expect(e.latestDueLatched(of: Std.today, at: Std.t(7, 17, 10)) == Std.guardRing(7))
    }

    @Test("next latched ring: the 'Snoozed until' time")
    func nextLatched() {
        let e = engine(armed)
        #expect(e.nextLatched(of: Std.today, after: Std.t(6, 42)) == Std.snooze(0))
        #expect(e.nextLatched(of: Std.today, after: Std.t(7, 7)) == Std.deadline())
        #expect(e.nextLatched(of: Std.today, after: Std.t(8, 10)) == nil)
    }

    @Test("C1: requiredChallenge is the ring's snapshotted kind at its level")
    func requiredChallenge() {
        let ring = Std.deadline(kind: .shake)
        #expect(engine(armed).requiredChallenge(for: ring) == ActiveChallenge(ring: ring, kind: .shake))
        #expect(engine(armed).requiredChallenge(for: ring).level == 3)
    }

    @Test("rings(of:) lists a morning's rings in target, oldest first")
    func ringsOfMorning() {
        #expect(engine(armed).rings(of: tomorrow) == Std.morning(tomorrow))
    }

    @Test("nextMorning skips the active morning, and is nil when the alarm is off")
    func nextMorning() {
        #expect(engine(armed).nextMorning(at: Std.t(21, 0, day: 15)) == Std.today)
        #expect(engine(armed).nextMorning(at: Std.t(6, 45)) == tomorrow)
        #expect(engine(armed) { $0.enabled = false }.nextMorning(at: Std.t(21, 0, day: 15)) == nil)
    }

    @Test("pendingAwakeChecks: first date of each group not confirmed or expired")
    func pendingAwakeChecks() {
        let solved = Std.t(6, 41)
        var state = EngineState(target: Std.awakeChecks(solvedAt: solved))
        state.finished[Std.today] = .solved
        #expect(engine(state).pendingAwakeChecks(at: Std.t(6, 42)) == [Std.t(6, 46), Std.t(6, 53)])
        state.acknowledged = ids(Std.awakeGroup(0, solvedAt: solved))
        state.target = Std.awakeGroup(1, solvedAt: solved)
        #expect(engine(state).pendingAwakeChecks(at: Std.t(6, 47)) == [Std.t(6, 53)])
    }

    @Test("position: rings are numbered in order and report their morning's deadline")
    func position() {
        let e = engine(armed)
        let main = e.position(of: Std.main())
        let snooze = e.position(of: Std.snooze(0))
        let deadline = e.position(of: Std.deadline())
        #expect(main.number < snooze.number)
        #expect(snooze.number < deadline.number)
        #expect(deadline.number <= deadline.total)
        #expect(deadline.deadline == Std.t(7, 10))
    }

    @Test("skipsLeft counts this calendar month's skips; hasScheduleError reports failed schedules")
    func skipsAndErrors() {
        var state = armed
        var ledger = SkipLedger()
        _ = ledger.use(at: Std.t(7, 0, day: 2), calendar: Std.calendar)
        state.skips = ledger
        state.failedSchedule = [Std.deadline().id]
        let e = engine(state)
        #expect(e.skipsLeft(at: Std.t(6, 0)) == 1)
        #expect(e.skipsLeft(at: Std.t(6, 0, day: 1, month: 12)) == 2)
        #expect(e.hasScheduleError)
        #expect(!engine(armed).hasScheduleError)
    }

    @Test("F7: a fresh engine on home without Bedside does not hold the screen awake")
    func idleTimerDefault() {
        #expect(!engine(armed).idleTimerDisabled(at: Std.t(6, 0)))
    }
}
