import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Regressions for the engine defects found while converging the suite with the engine (R1, R4, F1), and the
/// fuzz seeds that exposed them, kept as named cases.
@Suite("Converge: regressions found by the fuzz and grid")
struct ConvergeRegressionTests {
    func engine(_ state: EngineState) -> MorningEngine {
        MorningEngine(state: state, settings: SimFixture.standard.settings, calendar: Std.calendar)
    }

    @Test("R4: a new engine drops persisted pendingSchedule, so an alarm whose reply a kill lost is cancelled")
    func newEngineDropsStalePending() {
        let stale = Std.guardRing(5, of: Std.ideal(day: 19))
        var e = engine(EngineState(target: [], pendingSchedule: [stale.id]))
        #expect(e.state.pendingSchedule.isEmpty)
        let alarm = SystemAlarm(id: stale.id, fireDate: stale.date, ring: stale, alerting: false)
        let effects = e.handle(.systemTable([alarm], now: Std.t(21, 0, day: 15)))
        #expect(effects.contains(.cancel(stale.id)))
    }

    @Test("R1: the first event of a new engine reads the table, whatever it is; later idle events do not")
    func firstEventReadsTable() {
        var e = engine(EngineState(target: Std.morning()))
        let first = e.handle(.alertAction(ringID: Std.main().id, .openToChallenge, now: Std.t(6, 40, 5)))
        #expect(first.last == .readSystemTable)
        let second = e.handle(.tick(now: Std.t(6, 40, 10)))
        #expect(!second.contains(.readSystemTable))
    }

    @Test("R1: a systemTable as the first event never asks for another read")
    func firstSystemTableDoesNotReread() {
        var e = engine(EngineState())
        // The first pass a state ever runs saves `firstPass` (R2 orphan recovery is over); nothing else.
        #expect(e.handle(.systemTable([], now: Std.t(21, 0, day: 15))) == [.persist])
        #expect(e.handle(.systemTable([], now: Std.t(21, 0, 1, day: 15))) == [])
    }

    @Test("F1: an intent before launched plays nothing while inactive; launched opens the challenge silently")
    func soundSurvivesLaunched() {
        var e = engine(EngineState(target: Std.morning()))
        let now = Std.t(7, 17, 10)
        let guard7 = Std.guardRing(7)
        _ = e.handle(.alertAction(ringID: guard7.id, .openToChallenge, now: now))
        let alarm = SystemAlarm(id: guard7.id, fireDate: guard7.date, ring: guard7, alerting: true)
        let table = e.handle(.systemTable([alarm], now: now))
        // The process is not active yet, so no chime (F1, changed after the UI tests found background takeover).
        #expect(!table.contains(.sound(.play(nudge: false))))
        let launched = e.handle(.launched(now: now))
        #expect(e.screen == .challenge(ActiveChallenge(ring: guard7, kind: .math)))
        #expect(!launched.contains(.sound(.play(nudge: false))))
        #expect(e.session.sound == .stop)
    }

    @Test("P01 seed 1768: guards whose replies a kill lost leave AlarmKit once the alarm is turned off (INV8)")
    func seed1768() {
        #expect(PropertyTests.run(seed: 1768) == nil)
    }

    @Test("P01 seed 681: a background-started process reconciles at once after a pass a kill cut short (INV2)")
    func seed681() {
        #expect(PropertyTests.run(seed: 681) == nil)
    }

    @Test("P02 seed 100232: no awake check outlives its confirmation after a background cold start (INV5)")
    func seed100232() {
        #expect(PropertyTests.coldWarm(seed: 100_232) == nil)
    }
}
