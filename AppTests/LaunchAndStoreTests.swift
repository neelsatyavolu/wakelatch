import Foundation
import Testing
@testable import Wakelatch
import WakelatchCore

/// UI-test launch flags, the debug probe, the engine store and the move from the old UserDefaults keys.
@MainActor
struct LaunchAndStoreTests {
    private let now = Date(timeIntervalSince1970: 1_767_600_000)

    @Test func compressedTimingAndIdealFromNow() {
        let options = LaunchOptions.parse(["-uitest-timing", "compressed", "-uitest-ideal=90"], now: now, saved: nil)
        #expect(options.test?.timing == .compressed)
        #expect(options.test?.pinnedIdeal == now.addingTimeInterval(90))
        #expect(options.debug)
        #expect(options.tickInterval == .seconds(1))
    }

    @Test func soonIsCompressedWithoutNudges() {
        let options = LaunchOptions.parse(["-uitest-reset", "-uitest-onboarded", "-uitest-soon"], now: now, saved: nil)
        let timing = options.test?.timing(production: .production(PlanOptions()))
        #expect(options.reset && options.onboarded)
        #expect(timing?.nudgeOffsets == [])
        #expect(timing?.windowOverride == PlanTiming.compressed.windowOverride)
        #expect(options.test?.pinnedIdeal == now.addingTimeInterval(60))
    }

    @Test func faultAndAudibleFlags() {
        let plain = LaunchOptions.parse(["-uitest-slow-schedule", "-uitest-force-audible"], now: now, saved: nil)
        #expect(plain.test?.slowScheduleMilliseconds == 300)
        #expect(plain.test?.forceAudible == true)
        let valued = LaunchOptions.parse(["-uitest-slow-schedule=500", "-uitest-awake", "0"], now: now, saved: nil)
        #expect(valued.test?.slowScheduleMilliseconds == 500)
        #expect(valued.test?.awakeChecks == false)
    }

    /// A cold start by an alarm button has no launch arguments: the saved options stay until a reset.
    @Test func savedOptionsSurviveUntilReset() {
        let saved = TestOptions(timing: .compressed, pinnedIdeal: now)
        #expect(LaunchOptions.parse([], now: now, saved: saved).test == saved)
        #expect(LaunchOptions.parse(["-uitest-onboarded"], now: now, saved: saved).test == saved)
        #expect(LaunchOptions.parse(["-uitest-reset"], now: now, saved: saved).test == TestOptions())
    }

    @Test func productionHasNoTestOptions() {
        let options = LaunchOptions.parse(["/path/Wakelatch"], now: now, saved: nil)
        #expect(options == .production)
        #expect(!options.debug)
        #expect(!options.silent)
        #expect(options.tickInterval == .seconds(5))
    }

    /// The owner asked that no test run makes a sound: every `-uitest` flag is silent, the silence is saved
    /// for launches without arguments (an alert button starting the app), and the unit-test host is silent.
    @Test(arguments: [["-uitest-silent"], ["-uitest-onboarded"], ["-uitest-reset"], ["-uitest-show=ringing"],
                      ["-uitest-timing", "compressed"], ["-uitest-force-audible"], ["-uitest-soon"]])
    func everyUITestFlagIsSilent(args: [String]) {
        let options = LaunchOptions.parse(args, now: now, saved: nil)
        #expect(options.silent)
        #expect(options.test != nil)
        #expect(LaunchOptions.parse([], now: now, saved: options.test).silent)
    }

    @Test func unitTestHostIsSilent() {
        #expect(LaunchOptions.parse([], now: now, saved: nil, unitTestHost: true).silent)
        #expect(AppEnvironment.isUnitTestHost)
    }

    @Test func silentPlayerReportsWithoutPlaying() {
        let player = RingPlayer(silent: true)
        player.play(nudge: false)
        #expect(player.playing == .chime)
        player.play(nudge: true)
        #expect(player.playing == .nudge)
        player.stop()
        #expect(player.playing == nil)
    }

    @Test func debugStateDescribesTheChallenge() throws {
        let ring = Ring(date: now, kind: .deadline, level: 3, morning: now.addingTimeInterval(-120), challenge: .phrase)
        let table = [SystemAlarm(id: ring.id, fireDate: ring.date, ring: ring, alerting: true),
                     SystemAlarm(id: UUID(), fireDate: nil, ring: nil, alerting: false)]
        let state = EngineState(acknowledged: [UUID()])
        let json = DebugState(screen: .challenge(ActiveChallenge(ring: ring, kind: .math)), state: state,
                              table: table).json
        let decoded = try JSONDecoder().decode(DebugState.self, from: Data(json.utf8))
        #expect(decoded.screen == "challenge")
        #expect(decoded.ring == ring.id)
        #expect(decoded.kind == "deadline")
        #expect(decoded.level == 3)
        #expect(decoded.challenge == "math")
        #expect(decoded.acknowledged == 1)
        #expect(decoded.scheduled == 2)
        #expect(decoded.byKind == ["deadline": 1, "unknown": 1])
    }

    @Test func debugProbeOnlyUnderUITestFlags() {
        let device = Device()
        #expect(device.makeModel(options: .production).debugJSON == nil)
        #expect(device.makeModel().debugJSON != nil)
    }

    /// UI tests tell "the alert's intent never reached the app" (a simulator that can't run alert intents)
    /// apart from an app bug, so the count of intents received is kept across launches and shown in the probe.
    @Test func intentsReceivedAreCountedUnderUITestFlagsOnly() async throws {
        let device = Device()
        let model = device.makeModel()
        await model.receiveAlertAction(UUID(), .openToChallenge)
        let json = try #require(model.debugJSON)
        let decoded = try JSONDecoder().decode(DebugState.self, from: Data(json.utf8))
        #expect(decoded.intents == 1)
        #expect(decoded.skipsLeft == 2)
        #expect(device.makeModel().intentsReceived == 1)
        let production = device.makeModel(options: .production)
        await production.receiveAlertAction(UUID(), .openToChallenge)
        #expect(device.makeModel().intentsReceived == 1)
    }

    @Test func storeRoundTripsAndSurvivesGarbage() throws {
        let device = Device()
        let store = EngineStore(url: device.storeURL)
        #expect(store.load() == nil)
        let ring = Ring(date: now, kind: .main, level: 1, morning: now, challenge: .math)
        let state = EngineState(target: [ring], finished: [now.addingTimeInterval(-86_400): .solved],
                                route: PendingRoute(ringID: ring.id, at: now))
        try store.save(state)
        #expect(store.load() == state)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: device.folder.path(percentEncoded: false))
        #expect(leftovers == ["engine-state.json"])

        try Data("not json".utf8).write(to: device.storeURL)
        #expect(store.load() == nil)
    }

    @Test func legacyHistorySkipsAndRingsCarryOver() throws {
        let device = Device()
        let ideal = now
        let ringID = UUID()
        let legacy: [String: String] = [
            "records": #"[{"morning":\#(ideal.timeIntervalSinceReferenceDate),"ideal":0,"deadline":0,"upAt":\#(ideal.timeIntervalSinceReferenceDate + 60),"skipped":false},{"morning":0,"ideal":0,"deadline":0,"skipped":true}]"#,
            "skips": #"{"used":[\#(ideal.timeIntervalSinceReferenceDate)]}"#,
            "rings": #"[{"id":"\#(ringID.uuidString)","date":\#(ideal.timeIntervalSinceReferenceDate),"kind":"guardRing","level":3,"morning":\#(ideal.timeIntervalSinceReferenceDate)}]"#,
        ]
        for (key, json) in legacy { device.defaults.set(Data(json.utf8), forKey: key) }

        let result = try #require(LegacyMigration.run(device.storage))
        #expect(result.state.records.map(\.outcome) == [.solved, .skipped])
        #expect(result.state.finished[ideal] == .solved)
        #expect(result.state.skips.used == [ideal])
        #expect(result.ledger[ringID]?.kind == .guardRing)
        #expect(result.ledger[ringID]?.id == ringID)
        #expect(device.defaults.data(forKey: "records") == nil)
        #expect(LegacyMigration.run(device.storage) == nil)
    }
}
