import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// The invariant checker catches what it should, so a clean scenario really means the invariants held.
/// Synthetic steps; rings carry explicit ids.
@Suite("Harness: InvariantChecker catches violations")
struct InvariantCheckerTests {
    let settings = SimFixture.standard.settings
    let now = Std.t(7, 10, 30)
    let main = Ring(id: UUID(), date: Std.t(6, 40), kind: .main, level: 1, morning: Std.today, challenge: .math)
    let deadline = Ring(id: UUID(), date: Std.t(7, 10), kind: .deadline, level: 3, morning: Std.today, challenge: .math)
    let guardRing = Ring(id: UUID(), date: Std.t(7, 11), kind: .guardRing, level: 3, morning: Std.today, challenge: .math)

    var state: EngineState { EngineState(target: [main, deadline, guardRing]) }

    func table(_ rings: [Ring]) -> FakeAlarmKit {
        var kit = FakeAlarmKit()
        for ring in rings { kit.insert(ring) }
        return kit
    }

    func step(event: Event? = .tick(now: Std.t(7, 10, 30)), effects: [Effect] = [],
              processBefore: ProcessState = .foreground(.home), before: EngineState? = nil, after: EngineState? = nil,
              screenBefore: Screen = .none, screen: Screen = .none, session: SessionState = SessionState(),
              systemBefore: FakeAlarmKit? = nil, system: FakeAlarmKit? = nil, coverVisible: Bool = true,
              inFlight: Set<UUID> = [], quiescent: Bool = false, settled: Bool = false) -> SimStep {
        SimStep(now: now, event: event, effects: effects, processBefore: processBefore, process: .foreground(.home),
                before: before ?? state, after: after ?? before ?? state, screenBefore: screenBefore, screen: screen,
                session: session, systemBefore: systemBefore ?? table([guardRing]), system: system ?? table([guardRing]),
                coverVisible: coverVisible, inFlight: inFlight, quiescent: quiescent, reconcileSettled: settled)
    }

    func found(_ step: SimStep) -> Set<Invariant> {
        var checker = InvariantChecker()
        return Set(checker.observe(step, settings: settings, calendar: Std.calendar).map(\.invariant))
    }

    @Test("INV1: Released in the foreground while the deadline is due is caught; the deadline's ringing screen is not")
    func inv1() {
        let record = MorningRecord(morning: Std.ideal(day: 15), deadline: Std.t(7, 10, day: 15), outcome: .solved, upAt: nil)
        #expect(found(step(screen: .released(record))).contains(.inv1))
        #expect(!found(step(screen: .ringing(deadline, sounding: true, snoozedUntil: nil))).contains(.inv1))
        #expect(found(step(screen: .ringing(main, sounding: false, snoozedUntil: nil))).contains(.inv1))
    }

    @Test("INV2: a future latched ring of the active morning missing from AlarmKit is caught unless in flight")
    func inv2() {
        let missing = step(system: FakeAlarmKit(), quiescent: true)
        #expect(found(missing).contains(.inv2))
        #expect(!found(step(system: FakeAlarmKit(), inFlight: [guardRing.id], quiescent: true)).contains(.inv2))
    }

    @Test("INV3: a future guard of the active, unfinished morning leaving AlarmKit is caught; after a skip it is fine")
    func inv3() {
        #expect(found(step(system: FakeAlarmKit())).contains(.inv3))
        var skipped = state
        skipped.finished[Std.today] = .skipped
        #expect(!found(step(after: skipped, system: FakeAlarmKit())).contains(.inv3))
    }

    @Test("INV4: solved without an open challenge at the due level is caught")
    func inv4() {
        var solved = state
        solved.finished[Std.today] = .solved
        #expect(found(step(event: .solved(ringID: main.id, now: now), after: solved)).contains(.inv4))
        var withLowChallenge = state
        withLowChallenge.challenge = ActiveChallenge(ring: main, kind: .math)
        #expect(found(step(event: .solved(ringID: main.id, now: now), before: withLowChallenge, after: solved)).contains(.inv4))
        var withChallenge = state
        withChallenge.challenge = ActiveChallenge(ring: deadline, kind: .math)
        #expect(!found(step(event: .solved(ringID: deadline.id, now: now), before: withChallenge, after: solved)).contains(.inv4))
    }

    @Test("INV6: an outcome that changes after it was set is caught")
    func inv6() {
        var checker = InvariantChecker()
        var skipped = state
        skipped.finished[Std.today] = .skipped
        _ = checker.observe(step(after: skipped), settings: settings, calendar: Std.calendar)
        var missed = state
        missed.finished[Std.today] = .missed
        let second = checker.observe(step(before: skipped, after: missed), settings: settings, calendar: Std.calendar)
        #expect(second.contains { $0.invariant == .inv6 })
    }

    @Test("INV8: after a settled pass, an alarm missing from target is caught")
    func inv8() {
        let stray = Ring(id: UUID(), date: Std.t(9, 0), kind: .guardRing, level: 3, morning: Std.today, challenge: .math)
        #expect(found(step(event: nil, system: table([guardRing, stray]), quiescent: true, settled: true)).contains(.inv8))
    }

    @Test("INV9: silence behind a hidden cover is caught; a screen over an open sheet needs dismissHomeSheets first")
    func inv9() {
        #expect(found(step(effects: [.silence(deadline.id)], coverVisible: false)).contains(.inv9))
        #expect(!found(step(effects: [.silence(deadline.id)], coverVisible: true)).contains(.inv9))
        let ringing = Screen.ringing(deadline, sounding: true, snoozedUntil: nil)
        #expect(found(step(processBefore: .foreground(.sheet(.time)), screen: ringing)).contains(.inv9))
        #expect(!found(step(effects: [.dismissHomeSheets], processBefore: .foreground(.sheet(.time)), screen: ringing))
            .contains(.inv9))
    }

    @Test("INV10: a skip accepted with none left this month is caught")
    func inv10() {
        var ledger = SkipLedger()
        _ = ledger.use(at: Std.t(7, 0, day: 2), calendar: Std.calendar)
        _ = ledger.use(at: Std.t(7, 0, day: 9), calendar: Std.calendar)
        var before = state
        before.skips = ledger
        var after = before
        after.finished[Std.today] = .skipped
        #expect(found(step(event: .skip(ringID: deadline.id, now: now), before: before, after: after)).contains(.inv10))
    }
}
