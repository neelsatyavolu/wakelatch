import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// The harness itself: the fake AlarmKit and the sim's process rules (contract P1, B5). These do not need the
/// engine to do anything, so they pin the harness down independently of it. Rings here carry explicit ids.
@Suite("Harness: FakeAlarmKit and MorningSim processes")
struct HarnessTests {
    func ring(_ kind: RingKind, at date: Date, morning: Date = Std.today) -> Ring {
        Ring(id: UUID(), date: date, kind: kind, level: kind.latched ? 3 : 0, morning: morning,
             challenge: kind.latched ? .math : nil)
    }

    @Test("FakeAlarmKit: alarms alert once their date passes and leave the table when stopped")
    func fakeFiresAndStops() throws {
        var kit = FakeAlarmKit()
        let early = ring(.main, at: Std.t(6, 40))
        let late = ring(.snooze, at: Std.t(6, 49))
        try kit.schedule(early)
        try kit.schedule(late)
        #expect(kit.nextFireDate(after: Std.t(6, 0)) == Std.t(6, 40))
        #expect(kit.advance(to: Std.t(6, 40)) == [early.id])
        #expect(kit.alerting == [early.id])
        #expect(kit.advance(to: Std.t(6, 41)).isEmpty)
        #expect(kit.press(.stop, on: late.id) == nil)
        #expect(kit.press(.secondary, on: early.id) == .openToChallenge)
        #expect(!kit.contains(early.id))
        #expect(kit.live() == [late])
        #expect(kit.log == [.schedule(early.id), .schedule(late.id), .stop(early.id)])
    }

    @Test("FakeAlarmKit: a failing schedule throws, is logged, and leaves nothing behind")
    func fakeScheduleFails() {
        var kit = FakeAlarmKit()
        let r = ring(.deadline, at: Std.t(7, 10))
        #expect(throws: FakeAlarmKit.ScheduleFailure.self) { try kit.schedule(r, fails: [r.id]) }
        #expect(kit.ids.isEmpty)
        #expect(kit.log == [.scheduleFailed(r.id)])
    }

    @Test("FakeAlarmKit: the snapshot carries metadata rings, alerting flags and foreign alarms")
    func fakeSnapshot() throws {
        var kit = FakeAlarmKit()
        let r = ring(.guardRing, at: Std.t(7, 11))
        try kit.schedule(r)
        let foreign = UUID()
        kit.insertForeign(id: foreign, fireDate: Std.t(9, 0))
        _ = kit.advance(to: Std.t(7, 12))
        #expect(kit.snapshot == [SystemAlarm(id: r.id, fireDate: r.date, ring: r, alerting: true),
                                 SystemAlarm(id: foreign, fireDate: Std.t(9, 0), ring: nil, alerting: false)])
        kit.cancel(foreign)
        #expect(kit.ids == [r.id])
    }

    @Test("P1, B5: a locked device whose user cancels the unlock never runs a foreground intent")
    func lockedCancelDropsIntent() {
        var sim = MorningSim(start: Std.t(7, 12))
        let guardRing = ring(.guardRing, at: Std.t(7, 11))
        sim.plant(guardRing, alerting: true)
        sim.lock(cancelUnlock: true)
        #expect(sim.press(.stop, on: guardRing.id) == .openToChallenge)
        #expect(sim.eventLog.isEmpty)
        #expect(sim.engine == nil)
        #expect(sim.process == .locked(cancelUnlock: true))
        #expect(!sim.system.contains(guardRing.id))
    }

    @Test("P1: a system Stop that does nothing in the app sends no event and starts no process")
    func noneActionSendsNothing() {
        var sim = MorningSim(start: Std.t(6, 41))
        let main = ring(.main, at: Std.t(6, 40))
        sim.plant(main, alerting: true)
        #expect(sim.press(.stop, on: main.id) == AlertAction.none)
        #expect(sim.eventLog.isEmpty)
        #expect(sim.process == .killed)
    }

    @Test("P1: intent order on a killed process: alertAction relative to launched follows IntentOrder",
          arguments: IntentOrder.allCases)
    func coldIntentOrder(order: IntentOrder) throws {
        var sim = MorningSim(start: Std.t(7, 12), intentOrder: order)
        let guardRing = ring(.guardRing, at: Std.t(7, 11))
        sim.plant(guardRing, alerting: true)
        sim.press(.secondary, on: guardRing.id)
        let launched = try #require(sim.eventLog.firstIndex { if case .launched = $0 { true } else { false } })
        let action = try #require(sim.eventLog.firstIndex(where: isAlertAction))
        let tick = sim.eventLog.firstIndex { if case .tick = $0 { true } else { false } }
        switch order {
        case .beforeActive: #expect(action < launched)
        case .afterActive: #expect(launched < action)
        case .afterFirstTick:
            #expect(launched < action)
            #expect(try #require(tick) < action)
        }
        #expect(sim.process == .foreground(.home))
    }

    @Test("P1: intent order on a suspended process: alertAction relative to becameActive follows IntentOrder",
          arguments: IntentOrder.allCases)
    func warmIntentOrder(order: IntentOrder) throws {
        var sim = MorningSim(start: Std.t(7, 0), intentOrder: order)
        sim.launch()
        sim.show(.sheet(.settings))
        sim.suspend()
        let guardRing = ring(.guardRing, at: Std.t(7, 11))
        sim.plant(guardRing)
        sim.advance(to: Std.t(7, 12))
        let mark = sim.eventLog.count
        sim.press(.stop, on: guardRing.id)
        let events = sim.events(since: mark)
        let active = try #require(events.firstIndex { if case .becameActive = $0 { true } else { false } })
        let action = try #require(events.firstIndex(where: isAlertAction))
        #expect(order == .beforeActive ? action < active : active < action)
        #expect(!events.contains { if case .launched = $0 { true } else { false } })
        #expect(sim.process == .foreground(.sheet(.settings)))
    }

    @Test("B4: a background intent on a killed app runs without launched and leaves it in the background")
    func backgroundIntent() {
        var sim = MorningSim(start: Std.t(6, 47))
        let check = ring(.awakeCheck, at: Std.t(6, 46))
        sim.plant(check, alerting: true)
        #expect(sim.press(.secondary, on: check.id) == .confirmAwake)
        #expect(sim.eventLog.first == .alertAction(ringID: check.id, .confirmAwake, now: Std.t(6, 47)))
        let activations = sim.eventLog.filter {
            switch $0 {
            case .launched, .becameActive: true
            default: false
            }
        }
        #expect(activations.isEmpty)
        #expect(sim.process == .suspended)
    }

    @Test("a kill keeps only the disk; launch rebuilds the engine from it")
    func killKeepsDisk() {
        var disk = EngineState()
        disk.finished[Std.ideal(day: 15)] = .solved
        var sim = MorningSim(start: Std.t(6, 0), disk: disk)
        sim.launch()
        #expect(sim.engine?.state.finished == disk.finished)
        sim.kill()
        #expect(sim.engine == nil)
        #expect(sim.process == .killed)
        #expect(sim.state.finished == disk.finished)
    }

    @Test("foreground: alarms that start alerting are reported, and a tick arrives every 5 s; nothing while suspended")
    func foregroundEvents() {
        var sim = MorningSim(fixture: .standard { $0.enabled = false }, start: Std.t(6, 39, 30))
        sim.launch()
        // Planted after the first tick, whose confirming read (R1) would cancel it as unknown.
        sim.advance(to: Std.t(6, 39, 36))
        let main = ring(.main, at: Std.t(6, 40))
        sim.plant(main)
        sim.advance(to: Std.t(6, 40, 1))
        let alerting = sim.eventLog.contains { if case .alerting(let set, _, _, _) = $0 { set.contains(main.id) } else { false } }
        #expect(alerting)
        #expect(sim.eventLog.filter { if case .tick = $0 { true } else { false } }.count == 6)
        sim.suspend()
        let mark = sim.eventLog.count
        sim.advance(by: 600)
        #expect(sim.eventLog.count == mark)
    }

    @Test("show refuses home surfaces while nothing is foreground")
    func showNeedsForeground() {
        var sim = MorningSim(start: Std.t(6, 0))
        let whileKilled = sim.show(.bedside)
        #expect(!whileKilled)
        sim.launch()
        let whileForeground = sim.show(.bedside)
        #expect(whileForeground)
        #expect(sim.eventLog.contains(.bedsideChanged(true, now: Std.t(6, 0))))
    }
}
