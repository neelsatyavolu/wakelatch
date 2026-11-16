import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group R, named cases R10-R18 (contract B3-B5, S1, W3, F6).
@Suite("R: alert buttons, named cases 10-18")
struct AlertButtonNamedTests2 {
    func mainAlerting(_ fixture: SimFixture = .standard, order: IntentOrder = .afterActive) -> MorningSim {
        var sim = MorningSim.armed(fixture, order: order)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.advance(to: Std.t(6, 40, 10))
        return sim
    }

    /// A route stored by an intent whose app never came forward: the process dies right after persisting it.
    func strandedRoute(ring: Ring = Std.main()) -> MorningSim {
        var sim = mainAlerting(order: .beforeActive)
        sim.kill()
        sim.killAfter(effects: 0)
        sim.press(.secondary, on: ring.id)
        return sim
    }

    @Test("R10: the intent arriving before becameActive still opens the challenge, and it stays after ticks")
    func r10() {
        var sim = mainAlerting(order: .beforeActive)
        sim.press(.secondary, on: Std.main().id)
        let expected = Screen.challenge(ActiveChallenge(ring: Std.main(), kind: .math))
        #expect(sim.screen == expected)
        #expect(sim.state.route == nil)
        sim.advance(by: 10)
        #expect(sim.screen == expected)
        expectClean(sim)
    }

    @Test("R11: intent after the first tick: a ringing screen with chime is replaced by the challenge and the chime stops")
    func r11() {
        var sim = MorningSim.armed(order: .afterFirstTick)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.kill()
        sim.advance(to: Std.t(6, 49, 10))
        #expect(sim.alerting.isSuperset(of: [Std.main().id, Std.snooze(0).id]))
        let mark = sim.effectLog.count
        sim.press(.secondary, on: Std.main().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.snooze(0), kind: .math)))
        #expect(sim.sound == .silent)
        let sounds = sim.effects(since: mark).filter { if case .sound = $0 { true } else { false } }
        if playsChime(sounds) { #expect(sounds.last == .sound(.stop)) }
        expectClean(sim)
    }

    @Test("R12: a persisted route older than 120 s is ignored and cleared; the D1 snoozed screen shows")
    func r12() {
        var sim = strandedRoute()
        #expect(sim.disk.route == PendingRoute(ringID: Std.main().id, at: Std.t(6, 40, 10)))
        sim.advance(by: 121)
        sim.open()
        #expect(sim.screen == .ringing(Std.main(), sounding: false, snoozedUntil: Std.t(6, 49)))
        #expect(sim.state.route == nil)
        #expect(sim.state.challenge == nil)
        expectClean(sim)
    }

    @Test("R12: a persisted route exactly 120 s old is still honoured")
    func r12Boundary() {
        var sim = strandedRoute()
        sim.advance(by: 120)
        sim.open()
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        #expect(sim.state.route == nil)
        expectClean(sim)
    }

    @Test("R13: a route for a finished morning is ignored and cleared; the app opens on home")
    func r13() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.closeReleased()
        sim.suspend()
        sim.advance(to: Std.t(6, 42))
        sim.send(.alertAction(ringID: Std.snooze(0).id, .openToChallenge, now: sim.now))
        sim.open()
        #expect(sim.screen == .none)
        #expect(sim.state.route == nil)
        #expect(sim.state.challenge == nil)
        #expect(sim.state.finished[Std.today] == .solved)
        expectClean(sim)
    }

    @Test("R14: locked, Stop on a guard, unlock cancelled: nothing changes and the next guard still rings")
    func r14() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(7, 11, 30))
        sim.lock(cancelUnlock: true)
        sim.advance(to: Std.t(7, 12, 10))
        let disk = sim.disk
        let events = sim.eventLog.count
        #expect(sim.press(.stop, on: Std.guardRing(2).id) == .openToChallenge)
        #expect(sim.eventLog.count == events)
        #expect(sim.disk == disk)
        #expect(sim.process == .locked(cancelUnlock: true))
        #expect(ids((3...60).map { Std.guardRing($0) }).isSubset(of: sim.liveIDs(.guardRing)))
        sim.advance(to: Std.t(7, 13))
        #expect(sim.alerting.contains(Std.guardRing(3).id))
        expectClean(sim)
    }

    /// Solved at 06:41, app suspended, check 0 alerting at 06:46:10.
    func checkAlerting() -> MorningSim {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.suspend()
        sim.advance(to: Std.t(6, 46, 10))
        return sim
    }

    @Test("R15: awake 'I'm up' confirms group 0 in the background: cancelled, acknowledged, app not brought forward")
    func r15() {
        var sim = checkAlerting()
        let group = Std.awakeGroup(0, solvedAt: Std.t(6, 41))
        #expect(sim.press(.secondary, on: group[0].id) == .confirmAwake)
        #expect(sim.process == .suspended)
        #expect(sim.liveSystem(kind: .awakeCheck) == Std.awakeGroup(1, solvedAt: Std.t(6, 41)))
        #expect(ids(group).isSubset(of: sim.state.acknowledged))
        #expect(ids(group).isDisjoint(with: ids(sim.state.target)))
        #expect(ids(group).isSubset(of: sim.disk.acknowledged))
        expectClean(sim)
    }

    @Test("R16: awake Stop does exactly what 'I'm up' does")
    func r16() {
        var stop = checkAlerting()
        var imUp = checkAlerting()
        let check = Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 41))
        stop.press(.stop, on: check.id)
        imUp.press(.secondary, on: check.id)
        #expect(stop.state.acknowledged == imUp.state.acknowledged)
        #expect(stop.state.target == imUp.state.target)
        #expect(stop.liveSystem() == imUp.liveSystem())
        #expect(stop.process == imUp.process)
        expectClean(stop)
        expectClean(imUp)
    }

    @Test("R17: Released left up, the check takes over (S3) and clears Released; 'I'm up' confirms it and lands home (S6)")
    func r17() {
        var sim = MorningSim.armed()
        sim.solveToday(at: Std.t(6, 41))
        sim.advance(to: Std.t(6, 46, 10))
        let check = Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 41))
        #expect(sim.screen == .awakeCheck(check))
        #expect(sim.engine?.session.released == nil)
        sim.press(.secondary, on: check.id)
        #expect(sim.screen == .none)
        #expect(ids(Std.awakeGroup(0, solvedAt: Std.t(6, 41))).isDisjoint(with: sim.system.ids))
        expectClean(sim)
    }

    @Test("R18: 'I'm up' while suspended on the Settings sheet dismisses the sheet before the challenge shows")
    func r18() throws {
        var sim = MorningSim.armed(order: .beforeActive)
        sim.advanceStoppingSnoozes(to: Std.t(6, 39))
        sim.open(to: .sheet(.settings))
        #expect(sim.process == .foreground(.sheet(.settings)))
        sim.suspend()
        sim.advance(to: Std.t(6, 40, 10))
        let stepMark = sim.steps.count
        sim.press(.secondary, on: Std.main().id)
        #expect(sim.screen == .challenge(ActiveChallenge(ring: Std.main(), kind: .math)))
        #expect(sim.process == .foreground(.home))
        let shown = try #require(sim.steps[stepMark...].first { $0.screen != .none })
        let dismiss = try #require(shown.effects.firstIndex(of: .dismissHomeSheets))
        if let silence = shown.effects.firstIndex(where: { if case .silence = $0 { true } else { false } }) {
            #expect(dismiss < silence)
        }
        expectClean(sim)
    }
}
