import Foundation
import Testing
@testable import Wakelatch
import WakelatchCore

/// The app shell around the engine (plan 2.11): persistence before effects, intents on a cold start,
/// reconcile order, sheet dismissal and the idle timer, with a fake AlarmKit and a fake clock.
@MainActor
@Suite(.serialized)
struct ShellTests {
    /// R7: every schedule reaches AlarmKit only after a save that already lists its id as pending.
    @Test func shell01_effectsRunAfterPersist() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()

        let calls = device.log.entries
        let scheduled = calls.compactMap(\.scheduleStarted)
        #expect(scheduled.count == model.engine.state.target.count)
        #expect(!scheduled.isEmpty)
        for id in scheduled {
            let start = try #require(calls.firstIndex(of: .scheduleStart(id)))
            let persisted = calls[..<start].contains { $0.persistedPending?.contains(id) == true }
            #expect(persisted, "schedule of \(id) ran before a save listed it as pending")
        }
        #expect(device.saved?.target == model.engine.state.target)
        #expect(device.saved?.pendingSchedule.isEmpty == true)
    }

    /// B3/B5: "I'm up" starts a killed app. The intent arrives before `launched`; the route is saved before
    /// the intent returns, and the first activation lands on the challenge, never on home or ringing.
    @Test func shell02_coldIntentOpensChallenge() async throws {
        let device = Device()
        let first = device.makeModel()
        await first.open()
        let main = try #require(first.ring(.main))

        device.advance(to: 65)
        let relaunched = device.makeModel()
        let previous = IntentInbox.deliver
        IntentInbox.deliver = { id, action in await relaunched.receiveAlertAction(id, action) }
        defer { IntentInbox.deliver = previous }
        _ = try await OpenToChallengeIntent(ringID: main.id).perform()

        #expect(device.saved?.route?.ringID == main.id)
        await relaunched.open()
        guard case let .challenge(open) = relaunched.screen else {
            Issue.record("expected the challenge, got \(relaunched.screen)")
            return
        }
        #expect(open.ring.id == main.id)
        #expect(open.level == 1)
        #expect(device.saved?.route == nil)
        #expect(device.saved?.challenge == open)
    }

    /// B4: the awake-check button confirms in the background, and its cancels reach AlarmKit before the
    /// intent returns.
    @Test func shell02b_confirmAwakeIntentCancelsBeforeReturning() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()
        device.advance(to: 65)
        model.startChallenge(try #require(model.ring(.main)))
        guard case let .challenge(open) = model.screen else {
            Issue.record("no challenge")
            return
        }
        model.solved(open.ring)
        await model.alarmCallsSettled()
        let check = try #require(model.ring(.awakeCheck))
        let group = model.engine.state.target.filter { $0.kind == .awakeCheck && $0.checkGroup == check.checkGroup }

        let previous = IntentInbox.deliver
        IntentInbox.deliver = { id, action in await model.receiveAlertAction(id, action) }
        defer { IntentInbox.deliver = previous }
        _ = try await ConfirmAwakeIntent(ringID: check.id).perform()

        let held = await device.alarms.held
        for ring in group { #expect(held[ring.id] == nil) }
        #expect(!model.engine.state.target.contains { $0.checkGroup == check.checkGroup && $0.kind == .awakeCheck })
    }

    /// R2: the active morning's deadline and guards go out first, then its other latched rings, and the
    /// stray alarm is cancelled only after every one of those schedules has landed.
    @Test func shell03_reconcileRunsInEngineOrder() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()
        await device.alarms.removeAll()
        let stray = UUID()
        await device.alarms.addStray(id: stray, at: Device.start.addingTimeInterval(500))
        device.advance(to: 61)
        device.log.clear()

        model.scenePhaseChanged(.background)
        await model.open()

        let calls = device.log.entries.filter { $0.persistedPending == nil }
        let starts = calls.compactMap(\.scheduleStarted)
        let kinds = starts.compactMap { id in model.engine.state.target.first { $0.id == id }?.kind }
        #expect(kinds == [.deadline, .guardRing, .guardRing, .guardRing, .snooze, .snooze])
        let cancel = try #require(calls.firstIndex(of: .cancel(stray)))
        for id in starts {
            let end = try #require(calls.firstIndex(of: .scheduleEnd(id)))
            #expect(end < cancel)
        }
        // Serial: each schedule finishes before the next AlarmKit call starts.
        for (index, call) in calls.enumerated() {
            guard case let .scheduleStart(id) = call else { continue }
            #expect(calls[index + 1] == .scheduleEnd(id))
        }
    }

    /// F6: the screen leaving `.none` bumps the observable sheet-dismissal counter once.
    @Test func shell04_ringClosesHomeSheets() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()
        #expect(model.sheetDismissals == 0)

        device.advance(to: 60)
        let main = try #require(model.ring(.main))
        await device.alarms.setAlerting([main.id])
        model.alarmTableChanged(await device.alarms.table())

        #expect(model.screen == .ringing(main, sounding: true, snoozedUntil: nil))
        #expect(model.sheetDismissals == 1)
        #expect(device.sound.commands == [.play(nudge: false)])
        model.alarmTableChanged(await device.alarms.table())
        #expect(model.sheetDismissals == 1)
    }

    /// F7: the idle timer changes only through the engine's effect, and only when its value changes.
    @Test func shell05_idleTimerHasOneWriter() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()
        #expect(device.idleTimer.isEmpty)

        device.advance(to: 60)
        let main = try #require(model.ring(.main))
        await device.alarms.setAlerting([main.id])
        model.alarmTableChanged(await device.alarms.table())
        model.coverAppeared()
        #expect(device.idleTimer == [true])

        model.snooze(main)
        #expect(model.screen == .none)
        #expect(device.idleTimer == [true, false])

        model.bedside = true
        model.chargingChanged(true)
        #expect(device.idleTimer == [true, false, true])
        model.bedside = false
        #expect(device.idleTimer == [true, false, true, false])
        #expect(device.sound.commands == [.play(nudge: false), .stop])
    }

    /// A4: a one-off morning that ends turns the alarm off in the saved settings, and the engine accepts it.
    @Test func shell06_oneOffTurnsAlarmOff() async throws {
        let device = Device()
        var settings = UserSettings()
        settings.repeatDays = []
        settings.times = WakeTimes(ideal: ClockTime(hour: 8, minute: 10), deadline: ClockTime(hour: 8, minute: 12))
        device.storage.save(settings, key: Storage.settingsKey)
        let options = LaunchOptions(test: TestOptions(timing: .compressed, nudges: false))
        let model = device.makeModel(options: options)
        await model.open()
        #expect(model.engine.state.oneOffMorning != nil)

        // An hour later every ring has gone off and nobody answered: they are all still alerting. (Alarms of
        // a missed morning that never rang stay in AlarmKit; that only happens when the clock jumps, L3.)
        device.advance(to: 3600)
        await device.alarms.setAlerting(Set(await device.alarms.held.keys))
        model.send(.tick(now: device.now))
        await model.alarmCallsSettled()

        #expect(model.settings.enabled == false)
        #expect(device.storage.load(UserSettings.self, key: Storage.settingsKey)?.enabled == false)
        #expect(model.engine.settings.enabled == false)
        #expect(model.engine.state.records.last?.outcome == .missed)
        #expect(await device.alarms.held.isEmpty)
    }

    /// Releasing a solve with awake checks on schedules them, and a relaunch keeps them (no snapshot wipes them).
    @Test func shell07_awakeChecksSurviveRelaunch() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()
        device.advance(to: 65)
        model.startChallenge(try #require(model.ring(.main)))
        guard case let .challenge(open) = model.screen else {
            Issue.record("no challenge")
            return
        }
        model.solved(open.ring)
        await model.alarmCallsSettled()
        guard case .released = model.screen else {
            Issue.record("expected Released, got \(model.screen)")
            return
        }
        let checks = Set(model.engine.state.target.filter { $0.kind == .awakeCheck }.map(\.id))
        #expect(checks.count == 6)

        let relaunched = device.makeModel()
        await relaunched.open()
        let held = Set(await device.alarms.held.keys)
        #expect(held == checks)
    }
}
