import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// The detectors added or reworked in review fire on the defects they exist for (INV2, INV3, INV5, INV7,
/// INV11, INV12, INV13). Synthetic steps at 06:45 or 07:10:30 on the standard morning.
@Suite("Harness: InvariantChecker review detectors")
struct InvariantCheckerReviewTests {
    let settings = SimFixture.standard.settings
    let chain = Std.morning()

    func table(_ rings: [Ring]) -> FakeAlarmKit {
        var kit = FakeAlarmKit()
        for ring in rings { kit.insert(ring) }
        return kit
    }

    func step(at now: Date, event: Event? = nil, before: EngineState, after: EngineState? = nil,
              systemBefore: [Ring]? = nil, system: [Ring], screen: Screen = .none,
              session: SessionState = SessionState(), quiescent: Bool = false, settled: Bool = false,
              sound: SimSound = .silent, idle: Bool = false, current: Bool = true) -> SimStep {
        SimStep(now: now, event: event ?? .tick(now: now), effects: [], processBefore: .foreground(.home),
                process: .foreground(.home), before: before, after: after ?? before, screenBefore: screen,
                screen: screen, session: session, systemBefore: table(systemBefore ?? system),
                system: table(system), coverVisible: true, inFlight: [], quiescent: quiescent,
                reconcileSettled: settled, sound: sound, idleTimerDisabled: idle, outputsCurrent: current)
    }

    func future(at now: Date) -> [Ring] { chain.filter { $0.date > now } }

    @Test("Review 11 (INV3): a morning under way dropped from target, then cancelled a step later, is caught")
    func droppedMorningCaught() {
        var checker = InvariantChecker()
        let now = Std.t(6, 45)
        let full = EngineState(target: chain)
        let dropped = EngineState()
        _ = checker.observe(step(at: now, before: full, system: future(at: now)), settings: settings,
                            calendar: Std.calendar)
        let change = step(at: now, event: .settingsChanged(settings, now: now), before: full, after: dropped,
                          system: future(at: now))
        #expect(checker.observe(change, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv3 })
        let pass = step(at: now, event: .systemTable([], now: now), before: dropped, systemBefore: future(at: now),
                        system: [])
        #expect(checker.observe(pass, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv3 })
        let quiet = step(at: now, before: dropped, system: [], quiescent: true)
        #expect(checker.observe(quiet, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv2 })
    }

    @Test("Review 11 (INV3): a stale ring of the morning that target never held may be cancelled")
    func staleRingMayLeave() {
        var checker = InvariantChecker()
        let now = Std.t(6, 45)
        let stale = Ring(date: Std.t(7, 15, 25), kind: .snooze, level: 1, morning: Std.today, challenge: .math)
        let state = EngineState(target: chain)
        let pass = step(at: now, event: .systemTable([], now: now), before: state,
                        systemBefore: future(at: now) + [stale], system: future(at: now),
                        screen: .ringing(Std.main(), sounding: false, snoozedUntil: Std.snooze(0).date))
        #expect(checker.observe(pass, settings: settings, calendar: Std.calendar).isEmpty)
    }

    @Test("Review 12 (INV11): missed before the end, or skipped without a skip event, is caught; the real ones pass")
    func outcomesChecked() {
        let state = EngineState(target: chain)
        var missed = EngineState()
        missed.finished[Std.today] = .missed
        let early = Std.t(7, 10, 30)
        var checker = InvariantChecker()
        let earlyMiss = step(at: early, before: state, after: missed, system: [])
        #expect(checker.observe(earlyMiss, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv11 })
        let late = Std.t(8, 20, 1)
        var fresh = InvariantChecker()
        #expect(!fresh.observe(step(at: late, before: state, after: missed, system: []), settings: settings,
                               calendar: Std.calendar).contains { $0.invariant == .inv11 })
        var skipped = EngineState()
        skipped.finished[Std.today] = .skipped
        var unasked = InvariantChecker()
        #expect(unasked.observe(step(at: early, before: state, after: skipped, system: []), settings: settings,
                                calendar: Std.calendar).contains { $0.invariant == .inv11 })
        var asked = InvariantChecker()
        let skip = step(at: early, event: .skip(ringID: Std.deadline().id, now: early), before: state,
                        after: skipped, system: [])
        #expect(!asked.observe(skip, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv11 })
    }

    @Test("Review 15 (INV12): over the budget, or the next morning short of guards, is caught")
    func budgetAndGuardsChecked() {
        let now = Std.t(21, 0, day: 15)
        let mornings = (16...19).flatMap { Std.morning(Std.ideal(day: $0)) }
        var over = InvariantChecker()
        #expect(over.observe(step(at: now, before: EngineState(target: mornings), system: []), settings: settings,
                             calendar: Std.calendar).contains { $0.invariant == .inv12 })
        let short = Std.morning().filter { $0 != Std.guardRing(60) }
        var trimmed = InvariantChecker()
        #expect(trimmed.observe(step(at: now, before: EngineState(target: short), system: []), settings: settings,
                                calendar: Std.calendar).contains { $0.invariant == .inv12 })
        var whole = InvariantChecker()
        #expect(whole.observe(step(at: now, before: EngineState(target: Std.morning()), system: []),
                              settings: settings, calendar: Std.calendar).isEmpty)
    }

    @Test("Review 16 (INV13): a silent sounding screen, or an idle timer that disagrees with F7, is caught")
    func soundAndIdleChecked() {
        let now = Std.t(6, 40, 5)
        let state = EngineState(target: chain)
        let sounding = Screen.ringing(Std.main(), sounding: true, snoozedUntil: nil)
        let checks: [(SimStep, Bool)] = [
            (step(at: now, before: state, system: [], screen: sounding, quiescent: true, idle: true), true),
            (step(at: now, before: state, system: [], screen: sounding, quiescent: true,
                  sound: .playing(nudge: false), idle: false), true),
            (step(at: now, before: state, system: [], screen: sounding, quiescent: true,
                  sound: .playing(nudge: false), idle: true), false),
            (step(at: now, before: state, system: [], screen: sounding, quiescent: true, current: false), false),
        ]
        for (index, check) in checks.enumerated() {
            var checker = InvariantChecker()
            let caught = checker.observe(check.0, settings: settings, calendar: Std.calendar)
                .contains { $0.invariant == .inv13 }
            #expect(caught == check.1, "case \(index)")
        }
    }

    @Test("Review 17 (INV5, INV7): a missing awake check at the solve, a guard left after it, an unsynced ring")
    func inv5AndInv7Fire() {
        let now = Std.t(6, 41)
        var open = EngineState(target: chain)
        open.challenge = ActiveChallenge(ring: Std.main(), kind: .math)
        var solved = EngineState(target: Array(Std.awakeChecks(solvedAt: now).dropLast()))
        solved.finished[Std.today] = .solved
        var atSolve = InvariantChecker()
        let solve = step(at: now, event: .solved(ringID: Std.main().id, now: now), before: open, after: solved,
                         system: [])
        #expect(atSolve.observe(solve, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv5 })
        var settled = InvariantChecker()
        let leftover = step(at: now, before: solved, system: Array(solved.target) + [Std.guardRing(3)],
                            settled: true)
        #expect(settled.observe(leftover, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv5 })
        var unsynced = InvariantChecker()
        let tomorrow = EngineState(target: Std.morning(Std.ideal(day: 17)))
        let pass = step(at: now, before: tomorrow, system: [], settled: true)
        #expect(unsynced.observe(pass, settings: settings, calendar: Std.calendar).contains { $0.invariant == .inv7 })
    }
}
