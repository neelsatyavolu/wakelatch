import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group F: foreground and Bedside alerting, sound, silence, sheets, idle timer (contract F1-F8, S5, S6).
@Suite("F: sound, silence, sheets and the idle timer")
struct SoundAndSheetTests {
    /// Foreground at `start` (nudges stopped from the lock screen before), on `surface`.
    func foreground(at start: Date = Std.t(6, 39, 30), on surface: ForegroundSurface = .home,
                    audible: Bool = true, fixture: SimFixture = .standard) -> MorningSim {
        var sim = MorningSim.armed(fixture, audible: audible)
        sim.advanceStoppingSnoozes(to: start)
        sim.open(to: surface)
        return sim
    }

    @Test("F01 (F3, F5): Bedside, main alerts, audible: the app takes over with the chime and silences the system alarm")
    func f01() {
        var sim = foreground(on: .bedside)
        let mark = sim.effectLog.count
        sim.advance(to: Std.t(6, 40, 1))
        let effects = sim.effects(since: mark)
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        #expect(sim.sound == .playing(nudge: false))
        #expect(silenced(effects) == [Std.main().id])
        #expect(!sim.alerting.contains(Std.main().id))
        expectClean(sim)
    }

    @Test("F02 (F3): Bedside, main alerts, not audible: the app shows the ring but the system alarm keeps ringing")
    func f02() {
        var sim = foreground(on: .bedside, audible: false)
        let mark = sim.effectLog.count
        sim.advance(to: Std.t(6, 40, 1))
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        #expect(sim.sound == .playing(nudge: false))
        #expect(silenced(sim.effects(since: mark)).isEmpty)
        #expect(sim.alerting.contains(Std.main().id))
        expectClean(sim)
    }

    @Test("F03 (F2): in-app Snooze silences the system alarm even when the chime was not audible")
    func f03() {
        var sim = foreground(on: .bedside, audible: false)
        sim.advance(to: Std.t(6, 40, 1))
        let effects = sim.tapSnooze(Std.main().id)
        #expect(silenced(effects) == [Std.main().id])
        #expect(!sim.alerting.contains(Std.main().id))
        #expect(sim.sound == .silent)
        expectClean(sim)
    }

    @Test("F04 (F2, C1): in-app Start challenge silences the system alarm and opens the L1 challenge")
    func f04() {
        var sim = foreground(audible: false)
        sim.advance(to: Std.t(6, 40, 1))
        let effects = sim.tapStartChallenge(Std.main().id)
        #expect(silenced(effects) == [Std.main().id])
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        #expect(sim.sound == .silent)
        expectClean(sim)
    }

    @Test("F05 (F2): in-app nudge Stop silences the system nudge and goes home")
    func f05() {
        var sim = MorningSim.armed(audible: false)
        sim.advance(to: Std.t(6, 19, 30))
        sim.open()
        sim.advance(to: Std.t(6, 20, 1))
        #expect(sim.screen == .ringing(Std.nudge(0), sounding: true, snoozedUntil: nil))
        #expect(sim.sound == .playing(nudge: true))
        let effects = sim.tapNudgeStop(Std.nudge(0).id)
        #expect(silenced(effects) == [Std.nudge(0).id])
        #expect(sim.screen == .none)
        #expect(sim.sound == .silent)
        #expect(sim.state.acknowledged.contains(Std.nudge(0).id))
        expectClean(sim)
    }

    @Test("F06 (F4, C3): with the challenge open and in use, every snooze and the deadline are silenced in-app; it upgrades to L3")
    func f06() {
        var sim = foreground()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        let stepMark = sim.steps.count
        let chimeMark = sim.effectLog.count
        for ring in [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] {
            sim.advance(to: ring.date.addingTimeInterval(-5))
            sim.send(.challengeActivity(now: sim.now))
            let mark = sim.effectLog.count
            sim.advance(to: ring.date.addingTimeInterval(1))
            #expect(silenced(sim.effects(since: mark)).contains(ring.id), "\(ring.kind) at \(ring.date) silenced")
            #expect(!sim.alerting.contains(ring.id))
        }
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.deadline(), kind: .math)))
        #expect(!sim.screens(since: stepMark).contains { if case .ringing = $0 { true } else { false } })
        #expect(!playsChime(sim.effects(since: chimeMark)))
        expectClean(sim)
    }

    @Test("F07 (F4): with the challenge open and in use, each of the first 15 guards is silenced and the challenge follows it")
    func f07() {
        var sim = foreground(at: Std.t(7, 9, 30))
        sim.advance(to: Std.t(7, 10, 5))
        sim.tapStartChallenge(Std.deadline().id)
        for number in 1...15 {
            let ring = Std.guardRing(number)
            sim.advance(to: ring.date.addingTimeInterval(-5))
            sim.send(.challengeActivity(now: sim.now))
            sim.advance(to: ring.date.addingTimeInterval(1))
            #expect(!sim.alerting.contains(ring.id), "guard \(number) silenced")
            #expect(sim.openChallenge?.level == 3)
            #expect(sim.openChallenge?.morning == Std.today)
        }
        #expect(sim.alerting.isDisjoint(with: ids(Std.morning())))
        expectClean(sim)
    }

    @Test("F08 (S5): on Bedside the nudge screen survives ticks until it is tapped")
    func f08() {
        var sim = MorningSim.armed()
        sim.advance(to: Std.t(6, 19, 30))
        sim.open(to: .bedside)
        sim.advance(to: Std.t(6, 20, 1))
        let nudge = Screen.ringing(Std.nudge(0), sounding: true, snoozedUntil: nil)
        #expect(sim.screen == nudge)
        sim.advance(by: 30)
        #expect(sim.screen == nudge)
        #expect(sim.sound == .playing(nudge: true))
        sim.tapNudgeStop(Std.nudge(0).id)
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("F09 (S5): the nudge screen clears itself 5 minutes after it first showed")
    func f09() {
        var sim = MorningSim.armed()
        sim.advance(to: Std.t(6, 19, 30))
        sim.open(to: .bedside)
        sim.advance(to: Std.t(6, 24, 55))
        #expect(sim.screen == .ringing(Std.nudge(0), sounding: true, snoozedUntil: nil))
        sim.advance(to: Std.t(6, 25, 5))
        #expect(sim.screen == .none)
        #expect(sim.sound == .silent)
        expectClean(sim)
    }

    @Test("F10 (F5, F6, INV9): a ring over an open sheet dismisses it first and never silences behind the hidden cover")
    func f10() throws {
        var sim = foreground(on: .sheet(.time))
        let stepMark = sim.steps.count
        sim.advance(to: Std.t(6, 40, 1))
        let alertingStep = try #require(sim.steps[stepMark...].first {
            if case .alerting = $0.event { true } else { false }
        })
        #expect(alertingStep.effects.contains(.dismissHomeSheets))
        #expect(silenced(alertingStep.effects).isEmpty)
        #expect(sim.process == .foreground(.home))
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        let shown = try #require(sim.steps[stepMark...].first {
            if case .coverShown = $0.event { true } else { false }
        })
        #expect(silenced(shown.effects) == [Std.main().id])
        expectClean(sim)
    }

    @Test("F11 (F8): an alarm that started while the app was in the background is picked up on activation")
    func f11() throws {
        var sim = foreground(audible: false)
        sim.suspend()
        sim.advance(to: Std.t(6, 40, 20))
        let stepMark = sim.steps.count
        sim.open()
        let active = try #require(sim.steps[stepMark...].first { if case .becameActive = $0.event { true } else { false } })
        #expect(active.effects.contains(.readSystemTable))
        #expect(sim.engine?.session.alerting == [Std.main().id])
        #expect(sim.screen == .ringing(Std.main(), sounding: true, snoozedUntil: nil))
        expectClean(sim)
    }

    @Test("F12 (S3, F1): Released up, the check alerts: the check screen shows; the system alarm is the sound")
    func f12() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.advance(to: Std.t(6, 46, 1))
        let check = Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 41))
        #expect(sim.screen == .awakeCheck(check))
        #expect(sim.sound == .silent)
        #expect(sim.alerting.contains(check.id))
        expectClean(sim)
    }

    @Test("F13 (W3): in-app 'I'm up' on the check cancels its whole group and the check screen leaves")
    func f13() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.closeReleased()
        sim.advance(to: Std.t(6, 46, 1))
        let group = Std.awakeGroup(0, solvedAt: Std.t(6, 41))
        let effects = sim.tapImUp(group[0].id)
        #expect(effects.first == .persist)
        #expect(cancelled(effects) == ids(group))
        #expect(sim.screen == .none)
        #expect(ids(group).isDisjoint(with: sim.system.ids))
        expectClean(sim)
    }
}
