import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group F, idle timer and sound-on-change (contract F1, F6, F7).
@Suite("F: idle timer and sound changes")
struct IdleTimerTests {
    func idleEffects(_ effects: [Effect]) -> [Bool] {
        effects.compactMap { effect -> Bool? in
            if case .setIdleTimerDisabled(let value) = effect { return value }
            return nil
        }
    }

    @Test("F14 (F7): Bedside on the charger with keep-screen-on stays awake through ring and snooze, one writer")
    func f14() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39))
        sim.open(to: .bedside)
        sim.setCharging(true)
        #expect(sim.idleTimerDisabled)
        let mark = sim.effectLog.count
        sim.advance(to: Std.t(6, 40, 5))
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        sim.tapSnooze(Std.main().id)
        #expect(sim.screen == .none)
        sim.advance(to: Std.t(6, 45))
        #expect(sim.idleTimerDisabled)
        #expect(idleEffects(sim.effects(since: mark)).isEmpty)
        expectClean(sim)
    }

    @Test("F6: starting Bedside emits dismissHomeSheets")
    func bedsideDismissesSheets() {
        var sim = MorningSim.armed()
        sim.open()
        let effects = sim.send(.bedsideChanged(true, now: sim.now))
        #expect(effects.contains(.dismissHomeSheets))
    }

    @Test("F7: Bedside without the charger, or without keep-screen-on, lets the screen sleep")
    func bedsideNeedsChargerAndSetting() {
        var sim = MorningSim.armed()
        sim.open(to: .bedside)
        #expect(!sim.idleTimerDisabled)
        sim.setCharging(true)
        #expect(sim.idleTimerDisabled)
        sim.setCharging(false)
        #expect(!sim.idleTimerDisabled)

        var off = MorningSim.armed(.standard { $0.keepScreenOn = false })
        off.open(to: .bedside)
        off.setCharging(true)
        #expect(!off.idleTimerDisabled)
        expectClean(sim)
        expectClean(off)
    }

    @Test("F15 (F7): Released holds the screen awake for 60 s after the solve, then lets it sleep")
    func f15() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        #expect(sim.idleTimerDisabled)
        sim.advance(to: Std.t(6, 41, 30))
        #expect(sim.idleTimerDisabled)
        let mark = sim.effectLog.count
        sim.advance(to: Std.t(6, 42, 5))
        #expect(sim.screen == .released(Std.record(.solved, upAt: Std.t(6, 41))))
        #expect(!sim.idleTimerDisabled)
        #expect(idleEffects(sim.effects(since: mark)) == [false])
        expectClean(sim)
    }

    @Test("F15: going to the background clears Released and the screen may sleep")
    func releasedClearsOnBackground() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.suspend()
        #expect(sim.screen == .none)
        #expect(sim.engine?.session.released == nil)
        #expect(!sim.idleTimerDisabled)
        expectClean(sim)
    }

    @Test("F7: ringing, challenge and awake-check screens keep the screen awake")
    func morningScreensStayAwake() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        #expect(sim.idleTimerDisabled)
        sim.tapStartChallenge(Std.main().id)
        #expect(sim.idleTimerDisabled)
        sim.solveOpenChallenge()
        sim.closeReleased()
        #expect(!sim.idleTimerDisabled)
        sim.advance(to: Std.t(6, 45, 6))
        #expect(sim.screen == .awakeCheck(Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 40, 5))))
        #expect(sim.idleTimerDisabled)
        expectClean(sim)
    }

    @Test("F1: sound commands are sent only when they change; ticks while ringing send none")
    func soundOnlyOnChange() {
        var sim = MorningSim.armed(audible: false)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 1))
        #expect(sim.sound == .playing(nudge: false))
        let mark = sim.effectLog.count
        sim.advance(by: 30)
        #expect(!sim.effects(since: mark).contains { if case .sound = $0 { true } else { false } })
        sim.tapStartChallenge(Std.main().id)
        let afterChallenge = sim.effectLog.count
        #expect(sim.sound == .silent)
        sim.advance(by: 30)
        #expect(!sim.effects(since: afterChallenge).contains { if case .sound = $0 { true } else { false } })
        expectClean(sim)
    }
}
