import AVFoundation
import Foundation
import Testing
@testable import Wakelatch
import WakelatchCore

/// Review fixes in the app shell: takeover only with real in-app sound, an idle challenge, intent modes,
/// bundled sounds, the saved test profile in release builds, and the update from the 1.0 build.
@MainActor
@Suite(.serialized)
struct ReviewFixAppTests {
    /// Stops run in a detached task; give them time to reach the fake.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    /// Foreground, cover up, the main ring alerting at +60.
    private func mainAlerting(_ device: Device) async throws -> (AppModel, Ring) {
        let model = device.makeModel()
        await model.open()
        device.advance(to: 60)
        let main = try #require(model.ring(.main))
        await device.alarms.setAlerting([main.id])
        model.alarmTableChanged(await device.alarms.table())
        model.coverAppeared()
        try await settle()
        return (model, main)
    }

    /// F3: the system alarm is silenced only when the chime really started.
    @Test(arguments: [false, true])
    func takeoverNeedsTheChime(soundFails: Bool) async throws {
        let device = Device()
        device.sound.fails = soundFails
        let (model, main) = try await mainAlerting(device)
        #expect(model.screen == .ringing(main, sounding: true, snoozedUntil: nil))
        #expect(device.log.entries.contains(.stop(main.id)) == !soundFails)
    }

    /// An interruption stopped the chime. The next ring restarts it before silencing the system alarm, or
    /// leaves the system alarm ringing when it cannot restart.
    @Test(arguments: [false, true])
    func interruptedChimeIsRestartedOrTheAlarmRings(restartFails: Bool) async throws {
        let device = Device()
        let (model, _) = try await mainAlerting(device)
        device.sound.interrupt()
        device.sound.fails = restartFails

        device.advance(to: 101)
        let snooze = try #require(model.engine.state.target.first { $0.kind == .snooze })
        await device.alarms.setAlerting([snooze.id])
        model.alarmTableChanged(await device.alarms.table())
        try await settle()
        #expect(device.sound.commands.filter { $0 == .play(nudge: false) }.count >= 2)
        #expect(device.log.entries.contains(.stop(snooze.id)) == !restartFails)
        #expect((device.sound.playing != nil) == !restartFails)
    }

    /// F4: an open challenge without input lets the next ring sound; the next keystroke silences it.
    @Test func idleChallengeLetsTheNextRingSound() async throws {
        let device = Device()
        let (model, main) = try await mainAlerting(device)
        model.startChallenge(main)
        try await settle()
        #expect(device.log.entries.contains(.stop(main.id)))

        device.advance(to: 101)
        let snooze = try #require(model.engine.state.target.first { $0.kind == .snooze })
        await device.alarms.setAlerting([snooze.id])
        model.alarmTableChanged(await device.alarms.table())
        try await settle()
        guard case .challenge = model.screen else {
            Issue.record("expected the challenge, got \(model.screen)")
            return
        }
        #expect(!device.log.entries.contains(.stop(snooze.id)))

        model.challengeActivity()
        try await settle()
        #expect(device.log.entries.contains(.stop(snooze.id)))
    }

    /// B1, B3, B4: Stop and Solve on Deadline and guard alerts, and "I'm up" on main and snooze alerts, must
    /// open the app on the challenge. A background mode here would silence them without a challenge.
    @Test func intentModes() {
        #expect(OpenToChallengeIntent.supportedModes == .foreground(.immediate))
        #expect(OpenWakelatchIntent.supportedModes == .foreground(.immediate))
        #expect(ConfirmAwakeIntent.supportedModes == .background)
    }

    /// The in-app sounds are in the bundle and open as audio, without playing them.
    @Test(arguments: ["chime", "nudge", "silence"])
    func bundledSoundOpens(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "caf"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 0)
    }

    /// A release build ignores a profile a UI-test run left on the device.
    @Test func releaseBuildIgnoresASavedProfile() {
        let saved = TestOptions(timing: .compressed, pinnedIdeal: Device.start)
        #expect(LaunchOptions.savedProfile(saved, debugBuild: false) == nil)
        #expect(LaunchOptions.savedProfile(saved, debugBuild: true) == saved)
        let release = LaunchOptions.parse([], now: Device.start, saved: LaunchOptions.savedProfile(saved, debugBuild: false))
        #expect(release == .production)
        #expect(!release.silent)
    }

    /// B3 on a cold start: Stop on the Deadline alert opens the level-3 challenge.
    @Test func coldDeadlineStopOpensLevelThree() async throws {
        let device = Device()
        let first = device.makeModel()
        await first.open()
        let deadline = try #require(first.ring(.deadline))

        device.advance(to: 185)
        let relaunched = device.makeModel()
        let previous = IntentInbox.deliver
        IntentInbox.deliver = { id, action in await relaunched.receiveAlertAction(id, action) }
        defer { IntentInbox.deliver = previous }
        _ = try await AlarmRequest.make(for: deadline, silent: true).stopIntent?.perform()

        await relaunched.open()
        guard case let .challenge(open) = relaunched.screen else {
            Issue.record("expected the challenge, got \(relaunched.screen)")
            return
        }
        #expect(open.ring.id == deadline.id)
        #expect(open.level == 3)
    }

    /// Updating from the 1.0 build mid-morning: "I'm up" on that build's main alert opens the challenge.
    @Test func legacyMorningUnderWayOpensTheChallenge() async throws {
        let device = Device()
        let ideal = Device.start.addingTimeInterval(-60)
        let main = UUID()
        let legacy = [legacyRing(main, ideal, "main", 1, ideal),
                      legacyRing(UUID(), ideal.addingTimeInterval(540), "snooze", 1, ideal),
                      legacyRing(UUID(), ideal.addingTimeInterval(1800), "deadline", 3, ideal)]
        device.defaults.set(Data("[\(legacy.joined(separator: ","))]".utf8), forKey: "rings")

        let migrated = try #require(LegacyMigration.run(device.storage, now: Device.start))
        #expect(migrated.state.target.map(\.id).contains(main))
        try EngineStore(url: device.storeURL).save(migrated.state)
        let model = device.makeModel(options: LaunchOptions(debug: true, silent: true))
        await model.receiveAlertAction(main, .openToChallenge)
        await model.open()
        guard case let .challenge(open) = model.screen else {
            Issue.record("expected the challenge, got \(model.screen)")
            return
        }
        #expect(open.ring.id == main)
    }

    private func legacyRing(_ id: UUID, _ date: Date, _ kind: String, _ level: Int, _ morning: Date) -> String {
        #"{"id":"\#(id.uuidString)","date":\#(date.timeIntervalSinceReferenceDate),"kind":"\#(kind)","level":\#(level),"morning":\#(morning.timeIntervalSinceReferenceDate)}"#
    }
}
