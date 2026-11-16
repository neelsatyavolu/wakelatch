import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Bypasses and scheduling gaps found in review: an idle open challenge (F4), a clock moved forward (L3),
/// and an evening time change that cancelled tomorrow before scheduling it again (R2).
@Suite("Review fixes: idle challenge, clock jump, time-change order")
struct ReviewFixTests {
    /// Foreground on home with the main ring alerting at 06:40:05, then Start challenge.
    func challengeOpen() -> MorningSim {
        var sim = MorningSim.armed()
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 30))
        sim.open(to: .home)
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        return sim
    }

    @Test("F4: a challenge left without input does not silence the next ring; the next input does")
    func idleChallengeLetsTheRingSound() {
        var sim = challengeOpen()
        let snooze = Std.snooze(0)
        let mark = sim.effectLog.count
        sim.advance(to: snooze.date.addingTimeInterval(1))
        #expect(!silenced(sim.effects(since: mark)).contains(snooze.id))
        #expect(sim.alerting.contains(snooze.id))
        #expect(sim.openChallenge?.ring == Std.main(), "same level and kind: the challenge is kept (C3)")

        let effects = sim.send(.challengeActivity(now: sim.now))
        #expect(silenced(effects) == [snooze.id])
        #expect(!sim.alerting.contains(snooze.id))
        expectClean(sim)
    }

    @Test("F4: walking away from an open challenge never keeps the rest of the morning silent")
    func walkingAwayKeepsRinging() {
        var sim = challengeOpen()
        let mark = sim.effectLog.count
        var minute = Std.t(6, 41)
        var heard = Set<UUID>()
        while minute < Std.t(8, 30) {
            sim.advance(to: minute)
            heard.formUnion(sim.alerting)
            minute = minute.addingTimeInterval(30)
        }
        let silencedIDs = silenced(sim.effects(since: mark))
        #expect(silencedIDs.isEmpty)
        #expect(heard.isSuperset(of: ids([Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline()] + Std.guards())))
        expectClean(sim)
    }

    @Test("F4: with input every 20 s the challenge keeps silencing each ring as it alerts")
    func activeChallengeSilences() {
        var sim = challengeOpen()
        for ring in [Std.snooze(0), Std.snooze(1), Std.snooze(2), Std.deadline(), Std.guardRing(1)] {
            sim.advance(to: ring.date.addingTimeInterval(-10))
            sim.send(.challengeActivity(now: sim.now))
            let mark = sim.effectLog.count
            sim.advance(to: ring.date.addingTimeInterval(1))
            #expect(silenced(sim.effects(since: mark)).contains(ring.id), "\(ring.kind) at \(ring.date)")
            #expect(!sim.alerting.contains(ring.id))
        }
        #expect(sim.openChallenge?.level == 3)
        expectClean(sim)
    }

    @Test("L3: a clock moved past endsBy ends the morning, but its alarms that never rang stay in AlarmKit")
    func clockForwardKeepsAlarms() {
        let fixture = SimFixture.standard
        let real = Std.t(7, 10, 30)
        let rings = Std.morning()
        let table = rings.filter { $0.date >= Std.deadline().date }.map {
            SystemAlarm(id: $0.id, fireDate: $0.date, ring: $0, alerting: $0.id == Std.deadline().id)
        }
        var engine = MorningEngine(state: EngineState(target: rings, firstPass: Std.t(6, 0)),
                                   settings: fixture.settings, calendar: fixture.calendar)
        _ = engine.handle(.launched(now: real))
        _ = engine.handle(.systemTable(table, now: real))
        let jumped = real.addingTimeInterval(75 * 60)
        var effects = engine.handle(.calendarChanged(fixture.calendar, now: jumped))
        effects += engine.handle(.systemTable(table, now: jumped))
        let cancelled = Set(effects.compactMap { effect -> UUID? in
            if case let .cancel(id) = effect { return id }
            return nil
        })
        #expect(engine.state.finished[Std.today] == .missed)
        #expect(cancelled == [Std.deadline().id], "only the alarm still alerting is cancelled")
    }

    @Test("R2: an evening time change schedules the nearest morning before cancelling its old rings")
    func eveningChangeSchedulesTomorrowFirst() {
        var sim = MorningSim.armed()
        let old = sim.liveSystem(morning: Std.today)
        #expect(!old.isEmpty)
        let mark = sim.effectLog.count
        sim.changeSettings { $0.times.ideal = ClockTime(hour: 6, minute: 30) }
        let effects = sim.effects(since: mark)
        let newToday = Std.t(6, 30)
        let firstSchedule = effects.firstIndex { effect in
            if case let .schedule(ring) = effect { return ring.morning == newToday }
            return false
        }
        let firstOldCancel = effects.firstIndex { effect in
            if case let .cancel(id) = effect { return old.contains { $0.id == id } }
            return false
        }
        let lastFarCancel = effects.lastIndex { effect in
            if case let .cancel(id) = effect { return !old.contains { $0.id == id } }
            return false
        }
        guard let first = firstSchedule, let oldCancel = firstOldCancel, let farCancel = lastFarCancel else {
            Issue.record("expected schedules for the new morning and cancels of the old ones")
            return
        }
        #expect(first < oldCancel, "tomorrow's new rings go out before its old ones are cancelled")
        #expect(farCancel < first, "later mornings' old rings are cancelled first")
        #expect(!sim.liveSystem(morning: newToday).isEmpty)
        #expect(sim.liveSystem(morning: Std.today).isEmpty)
        expectClean(sim)
    }
}
