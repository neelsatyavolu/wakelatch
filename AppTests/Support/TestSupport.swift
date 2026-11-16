import Foundation
import Synchronization
@testable import Wakelatch
import WakelatchCore

/// One call the app made to a fake, in order.
enum Call: Equatable, Sendable {
    /// The engine state was saved; these ids were pending schedule at that moment.
    case persist(pending: Set<UUID>, route: PendingRoute?)
    case scheduleStart(UUID)
    case scheduleEnd(UUID)
    case cancel(UUID)
    case stop(UUID)
    case table

    /// The id of a schedule that started, nil for every other call.
    var scheduleStarted: UUID? {
        if case let .scheduleStart(id) = self { return id }
        return nil
    }

    /// The pending ids of a save, nil for every other call.
    var persistedPending: Set<UUID>? {
        if case let .persist(pending, _) = self { return pending }
        return nil
    }
}

/// Calls from the main actor and from the fake AlarmKit actor, in the order they happened.
final class CallLog: Sendable {
    private let calls = Mutex<[Call]>([])

    func append(_ call: Call) { calls.withLock { $0.append(call) } }
    func clear() { calls.withLock { $0.removeAll() } }
    var entries: [Call] { calls.withLock { $0 } }
}

struct FakeError: Error {}

/// AlarmKit in memory. Each schedule waits `latency`, so a runner that did not wait for it would let a
/// later call overtake it.
actor FakeAlarms: AlarmScheduling {
    let log: CallLog
    private(set) var held: [UUID: SystemAlarm] = [:]
    private var alerting: Set<UUID> = []
    private let latency: Duration

    init(log: CallLog, latency: Duration = .milliseconds(2)) {
        self.log = log
        self.latency = latency
    }

    func schedule(_ ring: Ring) async throws {
        log.append(.scheduleStart(ring.id))
        try? await Task.sleep(for: latency)
        held[ring.id] = SystemAlarm(id: ring.id, fireDate: ring.date, ring: ring, alerting: false)
        log.append(.scheduleEnd(ring.id))
    }

    func cancel(_ id: UUID) {
        held[id] = nil
        log.append(.cancel(id))
    }

    func stop(_ id: UUID) {
        alerting.remove(id)
        log.append(.stop(id))
    }

    func table() -> [SystemAlarm] {
        log.append(.table)
        return held.values.sorted { ($0.fireDate ?? .distantPast) < ($1.fireDate ?? .distantPast) }.map {
            SystemAlarm(id: $0.id, fireDate: $0.fireDate, ring: $0.ring, alerting: alerting.contains($0.id))
        }
    }

    nonisolated func alarmUpdates() -> AsyncStream<[SystemAlarm]> {
        AsyncStream { $0.finish() }
    }

    func setAlerting(_ ids: Set<UUID>) { alerting = ids }

    func removeAll() { held = [:] }

    /// An alarm the engine never asked for (left over from an older build), without a ring.
    func addStray(id: UUID, at date: Date) {
        held[id] = SystemAlarm(id: id, fireDate: date, ring: nil, alerting: false)
    }
}

/// The real file store, logging each save with what it held.
@MainActor
final class LoggingStore: EngineStoring {
    let file: EngineStore
    let log: CallLog

    init(url: URL, log: CallLog) {
        file = EngineStore(url: url)
        self.log = log
    }

    func load() -> EngineState? { file.load() }

    func save(_ state: EngineState) throws {
        try file.save(state)
        log.append(.persist(pending: state.pendingSchedule, route: state.route))
    }
}

@MainActor
final class RecordingSound: SoundPlaying {
    private(set) var commands: [SoundCommand] = []
    private(set) var playing: PlayingSound?
    /// The audio session refuses to start (a call, a missing file): `play` leaves nothing playing.
    var fails = false

    func play(nudge: Bool) {
        commands.append(.play(nudge: nudge))
        playing = fails ? nil : (nudge ? .nudge : .chime)
    }

    /// Another app, Siri or a call took the audio session: the player stopped by itself.
    func interrupt() {
        playing = nil
    }

    func stop() {
        commands.append(.stop)
        playing = nil
    }
}

/// One simulated device: its files, its AlarmKit and its clock. Each `makeModel()` is a new app process
/// on that device.
@MainActor
final class Device {
    static let start = Date(timeIntervalSince1970: 1_767_600_000)  // 2026-01-05 08:00 UTC

    let folder: URL
    let defaults: UserDefaults
    let log = CallLog()
    let alarms: FakeAlarms
    let sound = RecordingSound()
    var now = Device.start
    var charging = false
    private(set) var idleTimer: [Bool] = []

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "wakelatch-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "wakelatch-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        alarms = FakeAlarms(log: log)
    }

    var storeURL: URL { folder.appending(path: "engine-state.json") }
    var storage: Storage { Storage(defaults: defaults) }
    var saved: EngineState? { EngineStore(url: storeURL).load() }

    /// Compressed timing, no nudges, the morning's Ideal 60 s after `Device.start`: main at +60,
    /// snoozes at +100 and +140, the Deadline at +180, guards at +205, +230 and +255.
    static let pinned = LaunchOptions(test: TestOptions(timing: .compressed, pinnedIdeal: start.addingTimeInterval(60),
                                                        nudges: false), debug: true, silent: true)

    func makeModel(options: LaunchOptions = Device.pinned) -> AppModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let environment = AppEnvironment(
            store: LoggingStore(url: storeURL, log: log), settingsStore: storage, alarms: alarms, sound: sound,
            setIdleTimerDisabled: { [weak self] in self?.idleTimer.append($0) },
            now: { [weak self] in self?.now ?? Device.start }, calendar: { calendar }, audible: { true },
            isCharging: { [weak self] in self?.charging ?? false }, keepAlive: { _ in },
            tickInterval: .seconds(3600), options: options)
        return AppModel(environment: environment)
    }

    func advance(to seconds: TimeInterval) {
        now = Device.start.addingTimeInterval(seconds)
    }
}

extension AppModel {
    /// Opens the app (first activation sends `launched`) and waits for the reconcile pass to land.
    func open() async {
        scenePhaseChanged(.active)
        await alarmCallsSettled()
    }

    func ring(_ kind: RingKind) -> Ring? {
        engine.state.target.first { $0.kind == kind }
    }
}
