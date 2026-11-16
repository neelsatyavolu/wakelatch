import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Rules that cut across groups: S9, A5, A6 with the compressed profile, L3's boundary, K1's preconditions,
/// R1 and R7 over a whole morning.
@Suite("L: lifecycle and cross-cutting rules")
struct LifecycleTests {
    @Test("S9: after an in-app Snooze, the next latched ring brings the ringing screen back")
    func dismissedClearsOnNewerRing() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapSnooze(Std.main().id)
        #expect(sim.engine?.session.dismissedThisVisit == Std.main().id)
        sim.advance(to: Std.t(6, 49, 1))
        #expect(sim.screen == .ringing(Std.snooze(0), sounding: true, snoozedUntil: nil))
        #expect(sim.engine?.session.dismissedThisVisit == nil)
        expectClean(sim)
    }

    @Test("A5: with the alarm off nothing is armed")
    func disabledArmsNothing() {
        var sim = MorningSim(fixture: .standard { $0.enabled = false }, start: Std.t(21, 0, day: 15))
        sim.launch()
        #expect(sim.state.target.isEmpty)
        #expect(sim.system.ids.isEmpty)
        #expect(sim.engine?.nextMorning(at: sim.now) == nil)
        expectClean(sim)
    }

    @Test("A6, T3: a pinned compressed morning arms exactly that Ideal with the UI-test timing")
    func pinnedCompressedMorning() {
        let launch = Std.t(6, 0)
        let ideal = launch.addingTimeInterval(60)
        var sim = MorningSim(fixture: .standard {
            $0.timing = .compressed
            $0.pinnedMorning = ideal
        }, start: launch)
        sim.launch()
        let offsets = sim.liveSystem().map { $0.date.timeIntervalSince(ideal) }
        #expect(offsets == [-40, -20, 0, 40, 80, 120, 145, 170, 195])
        #expect(Set(sim.liveSystem().map(\.morning)) == [ideal])
        sim.advance(to: ideal.addingTimeInterval(5))
        #expect(sim.screen == .ringing(Std.main(of: ideal), sounding: true, snoozedUntil: nil))
        sim.tapStartChallenge(Std.main(of: ideal).id)
        sim.advance(to: ideal.addingTimeInterval(10))
        sim.solveOpenChallenge()
        let solved = ideal.addingTimeInterval(10)
        let checks = sim.liveSystem(kind: .awakeCheck).map { $0.date.timeIntervalSince(solved) }
        #expect(checks == [30, 50, 70, 70, 90, 110])
        expectClean(sim)
    }

    @Test("A6, T3, L3: an unsolved compressed morning is still on at last guard + 30 s and missed at the next tick")
    func compressedMissed() {
        let launch = Std.t(6, 0)
        let ideal = launch.addingTimeInterval(60)
        var sim = MorningSim(fixture: .standard {
            $0.timing = .compressed
            $0.pinnedMorning = ideal
        }, start: launch)
        sim.launch()
        sim.suspend()
        sim.advance(to: ideal.addingTimeInterval(225))
        sim.open()
        #expect(sim.state.finished[ideal] == nil)
        sim.advance(to: ideal.addingTimeInterval(231))
        #expect(sim.state.finished[ideal] == .missed)
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("L3: at 08:20:00 the last guard still shows; one second later the morning is missed")
    func missedBoundary() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(8, 20))
        sim.open()
        #expect(sim.screen == .ringing(Std.guardRing(60), sounding: true, snoozedUntil: nil))
        sim.advance(to: Std.t(8, 20, 5))
        #expect(sim.state.finished[Std.today] == .missed)
        #expect(sim.records.last == Std.record(.missed))
        #expect(sim.screen == .none)
        expectClean(sim)
    }

    @Test("K1: a skip naming a morning that has not started is refused")
    func skipNeedsActiveMorning() {
        var sim = MorningSim.armed()
        sim.open()
        let effects = sim.skip(Std.main().id)
        #expect(effects.isEmpty)
        #expect(sim.state.finished.isEmpty)
        #expect(sim.engine?.skipsLeft(at: sim.now) == 2)
        expectClean(sim)
    }

    @Test("B3, S1: a route naming an unknown ring is cleared and ignored")
    func unknownRoute() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        sim.send(.alertAction(ringID: UUID(), .openToChallenge, now: sim.now))
        #expect(sim.state.route == nil)
        #expect(sim.screen == .ringing(Std.main(), sounding: false, snoozedUntil: Std.t(6, 49)))
        expectClean(sim)
    }

    @Test("R7, R1: over a whole morning every state change persists first and every target change re-reads AlarmKit")
    func persistFirstAndReread() {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 45))
        sim.open()
        sim.changeSettings { $0.deadlineChallenge = .phrase }
        sim.tapStartChallenge(Std.main().id)
        sim.advance(to: Std.t(6, 58, 5))
        sim.solveOpenChallenge()
        sim.advance(to: Std.t(7, 3, 10))
        if case .awakeCheck(let check) = sim.screen { sim.tapImUp(check.id) }
        for step in sim.steps where step.stateChanged {
            #expect(step.effects.first == .persist, "\(step.event) changed state without persisting first")
        }
        for step in sim.steps where step.targetChanged && !step.isSystemTable {
            #expect(step.effects.contains(.readSystemTable), "\(step.event) changed target without a re-read")
        }
        let activations = sim.steps.filter {
            switch $0.event {
            case .launched, .becameActive: true
            default: false
            }
        }
        #expect(!activations.isEmpty)
        #expect(activations.allSatisfy { $0.effects.contains(.readSystemTable) })
        expectClean(sim)
    }

    @Test("R4: a later successful schedule of a failed id clears the error")
    func failedThenScheduled() {
        var sim = MorningSim.armed()
        sim.open()
        let id = Std.deadline().id
        sim.send(.scheduled(id, ok: false, now: sim.now))
        #expect(sim.engine?.hasScheduleError == true)
        #expect(sim.state.failedSchedule.contains(id))
        sim.send(.scheduled(id, ok: true, now: sim.now))
        #expect(sim.engine?.hasScheduleError == false)
        #expect(!sim.state.pendingSchedule.contains(id))
    }
}
