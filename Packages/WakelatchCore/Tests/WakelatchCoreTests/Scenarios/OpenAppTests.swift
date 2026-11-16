import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group O: opening the app from the icon, without an alert button (contract S1-S9, D1). Every case that can be
/// reached both ways is opened warm (suspended, becameActive) and cold (killed, launched), and the two must match.
@Suite("O: opening the app, cold equals warm")
struct OpenAppTests {
    /// Runs `history` on an armed, suspended sim, then opens it at `at` warm and cold. Expects the same screen
    /// and sound; returns both.
    func openBoth(at date: Date, start: Date = Std.t(21, 0, day: 15), fixture: SimFixture = .standard,
                  sourceLocation: SourceLocation = #_sourceLocation,
                  _ history: (inout MorningSim) -> Void = { _ in }) -> (warm: MorningSim, cold: MorningSim) {
        var sim = MorningSim.armed(fixture, at: start)
        history(&sim)
        sim.suspend()
        var warm = sim
        warm.advance(to: date)
        warm.open()
        var cold = sim
        cold.kill()
        cold.advance(to: date)
        cold.open()
        #expect(cold.screen == warm.screen, "cold equals warm (S8)", sourceLocation: sourceLocation)
        #expect(cold.sound == warm.sound, "cold equals warm (S8)", sourceLocation: sourceLocation)
        expectClean(warm, sourceLocation: sourceLocation)
        expectClean(cold, sourceLocation: sourceLocation)
        return (warm, cold)
    }

    @Test("O01: 06:00, nothing has rung: home")
    func o01() {
        let (warm, _) = openBoth(at: Std.t(6, 0))
        #expect(warm.screen == .none)
        #expect(warm.sound == .silent)
    }

    @Test("O02: 06:20:30 with the first nudge alerting: the nudge screen with its soft chime; one tap stops it")
    func o02() {
        var (warm, _) = openBoth(at: Std.t(6, 20, 30))
        #expect(warm.screen == .ringing(Std.nudge(0), sounding: true, snoozedUntil: nil))
        #expect(warm.sound == .playing(nudge: true))
        let effects = warm.tapNudgeStop(Std.nudge(0).id)
        #expect(silenced(effects) == [Std.nudge(0).id])
        #expect(warm.screen == .none)
        #expect(warm.sound == .silent)
        #expect(warm.system.contains(Std.main().id))
        expectClean(warm)
    }

    @Test("O03: 06:22 after the nudge was stopped from the system: home, and main is still scheduled")
    func o03() {
        let (warm, _) = openBoth(at: Std.t(6, 22)) { sim in
            sim.advance(to: Std.t(6, 20, 5))
            sim.press(.stop, on: Std.nudge(0).id)
        }
        #expect(warm.screen == .none)
        #expect(warm.system.contains(Std.main().id))
        #expect(warm.liveIDs(.guardRing) == ids(Std.guards()))
    }

    @Test("O04: 06:40:30 with main alerting: ringing, sounding, with the main chime")
    func o04() {
        let (warm, _) = openBoth(at: Std.t(6, 40, 30)) { $0.advanceStoppingSnoozes(to: Std.t(6, 39, 50)) }
        #expect(warm.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        #expect(warm.sound == .playing(nudge: false))
    }

    @Test("O05 (D1): 06:42 after main was stopped from the system: 'Snoozed until 06:49', never home")
    func o05() {
        let (warm, _) = openBoth(at: Std.t(6, 42)) { $0.advanceStoppingSnoozes(to: Std.t(6, 40, 5)) }
        #expect(warm.screen == .ringing(Std.main(), sounding: false, snoozedUntil: Std.t(6, 49)))
        #expect(warm.sound == .silent)
    }

    @Test("O06 (C9): in-app Snooze shows home for the rest of this visit, silences the system alarm, acknowledges main")
    func o06() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        let effects = sim.tapSnooze(Std.main().id)
        #expect(effects.first == .persist)
        #expect(silenced(effects) == [Std.main().id])
        #expect(sim.screen == .none)
        #expect(sim.state.acknowledged.contains(Std.main().id))
        #expect(sim.system.contains(Std.snooze(0).id))
        sim.advance(by: 5)
        #expect(sim.screen == .none)
        sim.advance(to: Std.t(6, 45))
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("O07 (D1): in-app Snooze, background, reopen at 06:45: the same snoozed screen as a system Stop")
    func o07() {
        let (warm, _) = openBoth(at: Std.t(6, 45)) { sim in
            sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
            sim.open()
            sim.advance(to: Std.t(6, 40, 5))
            sim.tapSnooze(Std.main().id)
        }
        #expect(warm.screen == .ringing(Std.main(), sounding: false, snoozedUntil: Std.t(6, 49)))
    }

    @Test("O08: 07:11:30 with deadline and guard 1 alerting, nothing pressed: guard 1 ringing, Solve only")
    func o08() {
        let (warm, _) = openBoth(at: Std.t(7, 11, 30)) { $0.advanceStoppingSnoozes(to: Std.t(7, 9, 50)) }
        #expect(warm.screen == .ringing(Std.guardRing(1), sounding: true, snoozedUntil: nil))
    }

    @Test("O09: a challenge started at 06:40 and left open is the L3 guard challenge at 07:12:30")
    func o09() {
        let (warm, _) = openBoth(at: Std.t(7, 12, 30)) { sim in
            sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
            sim.open()
            sim.advance(to: Std.t(6, 40, 5))
            sim.tapStartChallenge(Std.main().id)
        }
        #expect(warm.screen == .challenge(ActiveChallenge(ring: Std.guardRing(2), kind: .math)))
    }

    @Test("O10 (L3): past the last guard plus grace, never solved: home, recorded as missed, nothing left in AlarmKit")
    func o10() {
        let (warm, cold) = openBoth(at: Std.t(8, 21))
        for sim in [warm, cold] {
            #expect(sim.screen == .none)
            #expect(sim.state.finished[Std.today] == .missed)
            #expect(sim.records.filter { $0.morning == Std.today } == [Std.record(.missed)])
            #expect(sim.liveSystem(morning: Std.today).isEmpty)
        }
    }

    @Test("O11 (S6): Released left on screen in the foreground stays until a check is due")
    func o11Foreground() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 55))
        sim.advance(to: Std.t(6, 59, 30))
        #expect(sim.screen == .released(Std.record(.solved, upAt: Std.t(6, 55))))
        expectClean(sim)
    }

    @Test("O11 (S8): Released is never inherited by a later visit: reopening before the check shows home")
    func o11Reopen() {
        let (warm, _) = openBoth(at: Std.t(6, 59, 30)) { $0.solveToday(at: Std.t(6, 55)) }
        #expect(warm.screen == .none)
    }

    @Test("O12 (S3): 07:00:30 after a solve at 06:55, the 07:00 check is due: the awake-check screen")
    func o12() {
        let (warm, _) = openBoth(at: Std.t(7, 0, 30)) { $0.solveToday(at: Std.t(6, 55)) }
        #expect(warm.screen == .awakeCheck(Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 55))))
        #expect(warm.sound == .silent)
    }

    @Test("O13: yesterday's Released left up all night gives way to today's main ring")
    func o13() {
        let sunday = Std.ideal(day: 15)
        var sim = MorningSim.armed(at: Std.t(6, 0, day: 15))
        sim.tickInterval = 60
        sim.solveToday(at: Std.t(6, 41, day: 15), morning: sunday)
        sim.advance(to: Std.t(6, 41))
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        expectClean(sim)
    }

    @Test("O14 (C7): yesterday's challenge left open overnight: today's main rings; solving yesterday's ring does nothing")
    func o14() {
        let sunday = Std.ideal(day: 15)
        var (warm, _) = openBoth(at: Std.t(6, 41), start: Std.t(6, 0, day: 15)) { sim in
            sim.advance(to: Std.t(6, 40, 5, day: 15))
            sim.open()
            sim.tapStartChallenge(Std.main(of: sunday).id)
        }
        #expect(warm.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        #expect(warm.solve(Std.main(of: sunday).id).isEmpty)
        #expect(warm.state.finished[sunday] == .missed)
        #expect(warm.records.filter { $0.morning == sunday }.count == 1)
        warm.solve(Std.main().id)
        #expect(warm.state.finished[Std.today] == nil)
        expectClean(warm)
    }

    @Test("O15 (F6): suspended on the Settings sheet, opened at 06:45: the sheet is dismissed and main rings")
    func o15() {
        let (warm, cold) = openBoth(at: Std.t(6, 45)) { sim in
            sim.advanceStoppingSnoozes(to: Std.t(6, 39))
            sim.open(to: .sheet(.settings))
        }
        #expect(warm.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        #expect(warm.process == .foreground(.home))
        #expect(warm.effectLog.contains(.dismissHomeSheets))
        #expect(cold.process == .foreground(.home))
    }

    @Test("O16 (R5): a cold launch at 06:40 after a kill mid-sync shows main and refills the whole chain",
          arguments: [1, 3, 10, 40])
    func o16(killAfter: Int) {
        var sim = MorningSim(start: Std.t(21, 0, day: 15))
        sim.killAfter(effects: killAfter)
        sim.launch()
        sim.suspend()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.advance(to: Std.t(6, 40, 10))
        let mainAlerting = sim.alerting.contains(Std.main().id)
        sim.kill()
        sim.open()
        let until = mainAlerting ? nil : Std.t(6, 49)
        #expect(sim.screen == .ringing(Std.main(), sounding: mainAlerting, snoozedUntil: until))
        let rest = [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] + Std.guards()
        #expect(ids(rest).isSubset(of: sim.system.ids))
        expectClean(sim)
    }
}
