import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Engine branches the scenario groups do not reach: one-off bookkeeping (A4), a refused window (T6),
/// mornings without latched rings or a deadline ring, rings without a snapshotted kind, and skip by the open
/// challenge's ring.
@Suite("Engine: edge branches")
struct EngineBranchTests {
    static let oneOff = SimFixture.standard.with { $0.settings.repeatDays = [] }

    func engine(_ state: EngineState, _ change: (inout EngineSettings) -> Void = { _ in }) -> MorningEngine {
        var settings = SimFixture.standard.settings
        change(&settings)
        return MorningEngine(state: state, settings: settings, calendar: Std.calendar)
    }

    @Test("A4: a stored one-off is kept while unchanged, recomputed when Ideal moves, cleared when turned off")
    func oneOffBeforeItStarts() {
        var sim = MorningSim.armed(Self.oneOff)
        #expect(sim.state.oneOffMorning == Std.today)
        sim.open()
        #expect(sim.state.oneOffMorning == Std.today)
        sim.changeSettings { $0.times.ideal = ClockTime(hour: 6, minute: 30) }
        let moved = Std.t(6, 30)
        #expect(sim.state.oneOffMorning == moved)
        #expect(Set(sim.state.target.map(\.morning)) == [moved])
        sim.changeSettings { $0.enabled = false }
        #expect(sim.state.oneOffMorning == nil)
        #expect(sim.state.target.isEmpty)
        expectClean(sim)
    }

    @Test("A4, D3: once the one-off has started, a refresh keeps it alone, even with the alarm turned off")
    func oneOffUnderWay() {
        var sim = MorningSim.armed(Self.oneOff)
        sim.advanceStoppingSnoozes(to: Std.t(6, 25))
        sim.open()
        let rings = sim.state.target
        sim.changeSettings { $0.keepScreenOn.toggle() }
        #expect(sim.state.oneOffMorning == Std.today)
        #expect(sim.state.target == rings)
        sim.changeSettings { $0.enabled = false }
        #expect(sim.state.oneOffMorning == Std.today)
        #expect(sim.state.target == rings)
        #expect(sim.engine?.underWay(at: sim.now)?.morning == Std.today)
        expectClean(sim)
    }

    @Test("T6, G1: a window over 180 min arms nothing new; the morning under way keeps every ring")
    func windowTooLongDuringMorning() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        let today = Oracle.rings(of: Std.today, in: sim.state.target)
        sim.changeSettings { $0.times.deadline = ClockTime(hour: 10, minute: 0) }
        #expect(sim.state.target == today)
        #expect(sim.engine?.nextMorning(at: sim.now) == nil)
        expectClean(sim)
    }

    @Test("L1, L5: a morning holding only nudges ends grace after its last ring; its deadline comes from the window")
    func nudgesOnlyMorning() {
        let e = engine(EngineState(target: [Std.nudge(0), Std.nudge(1)]))
        #expect(e.activeMorning(at: Std.t(6, 25)) == Std.today)
        #expect(e.underWay(at: Std.t(6, 25)) == UnderWay(morning: Std.today, deadline: Std.t(7, 10), endsBy: Std.t(6, 40)))
        #expect(e.activeMorning(at: Std.t(6, 40, 1)) == nil)
    }

    @Test("position of a ring not in target is the first of its morning's latched rings")
    func positionOfUnknownRing() {
        let e = engine(EngineState(target: Std.morning()))
        let stray = Ring(date: Std.t(6, 44), kind: .snooze, level: 1, morning: Std.today, challenge: .math)
        let position = e.position(of: stray)
        #expect(position.number == 1)
        #expect(position.total == Std.latched().count)
    }

    @Test("pendingAwakeChecks groups an awake check without a group as group 0")
    func awakeCheckWithoutGroup() {
        let check = Ring(date: Std.t(6, 46), kind: .awakeCheck, level: 0, morning: Std.today)
        var state = EngineState(target: [check])
        state.finished[Std.today] = .solved
        #expect(engine(state).pendingAwakeChecks(at: Std.t(6, 47)) == [Std.t(6, 46)])
    }

    @Test("C1, C6: a latched ring without a snapshotted kind requires math, and math solves it")
    func ringWithoutKind() {
        let main = Ring(date: Std.today, kind: .main, level: 1, morning: Std.today)
        var e = engine(EngineState(target: [Std.nudge(0), main]))
        #expect(e.requiredChallenge(for: main) == ActiveChallenge(ring: main, kind: .math))
        _ = e.handle(.launched(now: Std.t(6, 40, 5)))
        _ = e.handle(.tapStartChallenge(main.id, now: Std.t(6, 40, 6)))
        #expect(e.state.challenge == ActiveChallenge(ring: main, kind: .math))
        _ = e.handle(.solved(ringID: main.id, now: Std.t(6, 41)))
        #expect(e.state.finished[Std.today] == .solved)
    }

    @Test("K1: skip names the open challenge's ring even when that ring is not in target; an unknown id is refused")
    func skipByChallengeRing() {
        let stray = Ring(date: Std.t(6, 39), kind: .snooze, level: 1, morning: Std.today, challenge: .math)
        let state = EngineState(target: Std.morning(), challenge: ActiveChallenge(ring: stray, kind: .math))
        var e = engine(state)
        _ = e.handle(.launched(now: Std.t(6, 45)))
        #expect(e.state.challenge?.ring == stray)
        _ = e.handle(.skip(ringID: UUID(), now: Std.t(6, 45, 5)))
        #expect(e.state.finished[Std.today] == nil)
        _ = e.handle(.skip(ringID: stray.id, now: Std.t(6, 45, 10)))
        #expect(e.state.finished[Std.today] == .skipped)
        #expect(e.screen == .none)
    }

    @Test("S2: a persisted challenge whose morning has no due latched ring is cleared, and S3-S7 decide")
    func challengeWithoutDueRing() {
        let state = EngineState(target: Std.morning(), challenge: ActiveChallenge(ring: Std.main(), kind: .math))
        var e = engine(state)
        _ = e.handle(.launched(now: Std.t(6, 25)))
        #expect(e.state.challenge == nil)
        #expect(e.screen == .none)
    }

    @Test("B2: an alert action of .none changes nothing")
    func alertActionNone() {
        var e = engine(EngineState(target: Std.morning()))
        _ = e.handle(.launched(now: Std.t(6, 20, 5)))
        let before = e.state
        #expect(e.handle(.alertAction(ringID: Std.nudge(0).id, .none, now: Std.t(6, 20, 6))) == [])
        #expect(e.state == before)
    }

    @Test("R2: an alarm without a fire date is adopted by its ring's date")
    func adoptWithoutFireDate() {
        let ring = Std.guardRing(5)
        let alarm = SystemAlarm(id: ring.id, fireDate: nil, ring: ring, alerting: false)
        let plan = Reconciler.plan(target: [], system: [alarm], pending: [], activeMorning: Std.today,
                                   now: Std.t(7, 0))
        #expect(plan.adopt.map(\.id) == [ring.id])
        #expect(plan.cancel.isEmpty)
    }
}
