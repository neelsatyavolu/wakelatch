import AVFoundation
import CoreMotion
@preconcurrency import AlarmKit
import Foundation
import Testing
@testable import Wakelatch
import WakelatchCore

/// The few rules the views hold: which buttons a ringing screen offers, when a sensor challenge can run,
/// and that a sensor falling back or a snooze being reopened lands where the contract says.
@MainActor
@Suite(.serialized)
struct ViewRulesTests {
    /// Plan Shell05 (fix 6): a refused or restricted permission makes the kind unusable; not asked yet does not.
    @Test func capabilitiesHonourDeniedPermission() {
        #expect(SensorAccess(camera: .authorized) == .granted)
        #expect(SensorAccess(camera: .notDetermined) == .notAsked)
        #expect(SensorAccess(camera: .denied) == .denied)
        #expect(SensorAccess(camera: .restricted) == .denied)
        #expect(SensorAccess(motion: .authorized) == .granted)
        #expect(SensorAccess(motion: .notDetermined) == .notAsked)
        #expect(SensorAccess(motion: .denied) == .denied)
        #expect(SensorAccess(motion: .restricted) == .denied)

        #expect(Capabilities.usable(hardware: true, access: .granted))
        #expect(Capabilities.usable(hardware: true, access: .notAsked))
        #expect(!Capabilities.usable(hardware: true, access: .denied))
        #expect(!Capabilities.usable(hardware: false, access: .granted))
        #expect(Capabilities.supports(.math))
        #expect(Capabilities.supports(.phrase))
    }

    /// Fix 6: at alarm time a sensor challenge runs only with permission already given, so no prompt shows
    /// during the alarm; not asked, denied or no hardware all fall back to math.
    @Test func challengeRunsOnlyWithPermissionGiven() {
        #expect(Capabilities.ready(hardware: true, access: .granted))
        #expect(!Capabilities.ready(hardware: true, access: .notAsked))
        #expect(!Capabilities.ready(hardware: true, access: .denied))
        #expect(!Capabilities.ready(hardware: false, access: .granted))
        #expect(Capabilities.canRunNow(.math))
        #expect(Capabilities.canRunNow(.phrase))
    }

    /// S4, C8, D1: Snooze only on a sounding main or snooze ring; the deadline and guards offer only Solve.
    @Test(arguments: RingKind.allCases, [true, false])
    func ringingButtons(kind: RingKind, sounding: Bool) {
        let ring = Ring(date: Device.start, kind: kind, level: kind.latched ? 1 : 0, morning: Device.start)
        let buttons = RingingButton.buttons(for: ring, sounding: sounding)
        switch kind {
        case .nudge: #expect(buttons == [.stopNudge])
        case .main, .snooze: #expect(buttons == (sounding ? [.startChallenge, .snooze] : [.startChallenge]))
        case .deadline, .guardRing, .awakeCheck: #expect(buttons == [.solve])
        }
    }

    /// C4: a sensor the phone can't run switches the open challenge to math on the same ring, and solving
    /// that math releases the morning.
    @Test func sensorFallbackSwitchesToMath() async throws {
        let device = Device()
        let model = device.makeModel()
        model.update { $0.snoozeChallenge = .shake }
        await model.open()

        device.advance(to: 60)
        let main = try #require(model.ring(.main))
        #expect(main.challenge == .shake)
        model.startChallenge(main)
        #expect(model.screen == .challenge(ActiveChallenge(ring: main, kind: .shake)))

        model.challengeUnavailable(.shake)
        #expect(model.screen == .challenge(ActiveChallenge(ring: main, kind: .math)))

        model.solved(main)
        guard case .released = model.screen else {
            Issue.record("expected Released, got \(model.screen)")
            return
        }
    }

    /// D1: after an in-app Snooze, reopening the app shows "Snoozed until" with only Start challenge.
    @Test func reopenAfterSnoozeOffersOnlyTheChallenge() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.open()

        device.advance(to: 60)
        let main = try #require(model.ring(.main))
        await device.alarms.setAlerting([main.id])
        model.alarmTableChanged(await device.alarms.table())
        model.snooze(main)
        #expect(model.screen == .none)
        await model.alarmCallsSettled()
        await device.alarms.setAlerting([])

        device.advance(to: 70)
        model.scenePhaseChanged(.background)
        await model.open()
        let next = try #require(model.latchedRings(of: main.morning).first { $0.date > main.date })
        #expect(model.screen == .ringing(main, sounding: false, snoozedUntil: next.date))
        #expect(RingingButton.buttons(for: main, sounding: false) == [.startChallenge])
    }

    /// AlarmKit's permission is read off the main thread, so until the first read lands it is unknown and
    /// home must not claim alarms are off. Gaining it after launch re-reads the table so failed schedules retry.
    @Test func alarmPermissionUnknownUntilRead() async {
        let device = Device()
        let model = device.makeModel()
        #expect(model.alarmsAuthorized == nil)
        await model.open()
        model.applyAuthorization(.denied)
        #expect(model.alarmsAuthorized == false)

        device.log.clear()
        model.applyAuthorization(.authorized)
        await model.alarmCallsSettled()
        #expect(model.alarmsAuthorized == true)
        #expect(device.log.entries.contains(.table))
    }
}
