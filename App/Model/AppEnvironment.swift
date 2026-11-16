import Foundation
import os
import UIKit
import WakelatchCore

let modelLog = Logger(subsystem: "co.xanom.wakelatch", category: "model")

/// Plays the in-app chime. `RingPlayer` in the app, a recorder in tests.
@MainActor
protocol SoundPlaying: AnyObject {
    /// What is playing now (or, when silent, what would be).
    var playing: PlayingSound? { get }
    func play(nudge: Bool)
    func stop()
}

/// Everything AppModel needs from outside, so tests can replace each piece.
@MainActor
struct AppEnvironment {
    var store: any EngineStoring
    var settingsStore: Storage
    var alarms: any AlarmScheduling
    var sound: any SoundPlaying
    /// The only writer of `UIApplication.isIdleTimerDisabled` (contract F7).
    var setIdleTimerDisabled: @MainActor (Bool) -> Void
    var now: @MainActor () -> Date
    var calendar: @MainActor () -> Calendar
    /// The media volume is high enough for the in-app chime to wake someone (takeover, contract F3).
    var audible: @MainActor () -> Bool
    var isCharging: @MainActor () -> Bool
    /// Asks iOS for background time while AlarmKit calls are queued (true) and releases it (false).
    var keepAlive: @MainActor (Bool) -> Void
    var tickInterval: Duration
    var options: LaunchOptions

    /// The process is the host of the WakelatchTests unit tests: the app must not start its model.
    nonisolated static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

extension AppEnvironment {
    /// The real app: files in Application Support, AlarmKit, UIKit.
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        let settingsStore = Storage()
        let saved = LaunchOptions.savedProfile(settingsStore.load(TestOptions.self, key: TestOptions.storageKey))
        let options = LaunchOptions.parse(arguments, now: .now, saved: saved, unitTestHost: isUnitTestHost)
        let folder = EngineStore.defaultFolder
        let store = EngineStore(url: folder.appending(path: "engine-state.json"))
        let ledgerURL = folder.appending(path: "alarm-ledger.json")
        let simulatedURL = folder.appending(path: "simulated-alarms.json")
        if options.reset {
            settingsStore.removeAll()
            store.remove()
            try? FileManager.default.removeItem(at: ledgerURL)
            try? FileManager.default.removeItem(at: simulatedURL)
        }
        if let test = options.test { settingsStore.save(test, key: TestOptions.storageKey) }
        var seed: [UUID: Ring] = [:]
        if !store.exists, let migrated = LegacyMigration.run(settingsStore) {
            try? store.save(migrated.state)
            seed = migrated.ledger
        }
        let delay = options.test?.slowScheduleMilliseconds.map { Duration.milliseconds($0) }
        let background = BackgroundWork()
        return AppEnvironment(
            store: store, settingsStore: settingsStore,
            alarms: options.test?.simulatedAlarms == true
                ? SimulatedAlarms(url: simulatedURL, scheduleDelay: delay)
                : AlarmDriver(ledger: RingLedger(url: ledgerURL, rings: seed), scheduleDelay: delay,
                              silent: options.silent),
            sound: RingPlayer(silent: options.silent),
            setIdleTimerDisabled: { UIApplication.shared.isIdleTimerDisabled = $0 },
            now: { .now }, calendar: { .current },
            audible: { options.test?.forceAudible == true || RingPlayer.volumeIsAudible },
            isCharging: { [.charging, .full].contains(UIDevice.current.batteryState) },
            keepAlive: { background.set($0) },
            tickInterval: options.tickInterval, options: options)
    }
}

/// Holds one UIKit background task while AlarmKit calls are queued, so leaving the app mid-pass still
/// finishes it. Reconcile is crash-safe anyway (R5); this only makes the common case complete sooner.
@MainActor
final class BackgroundWork {
    private var task: UIBackgroundTaskIdentifier = .invalid

    func set(_ running: Bool) {
        if running, task == .invalid {
            task = UIApplication.shared.beginBackgroundTask(withName: "Schedule alarms") { [weak self] in
                self?.set(false)
            }
        } else if !running, task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }
}
