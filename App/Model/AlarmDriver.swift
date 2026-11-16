@preconcurrency import AlarmKit
import Foundation
import WakelatchCore

/// The only caller of AlarmKit's scheduling API. AppModel runs its calls one at a time, in the order the
/// engine gave them, and turns each result into an event.
actor AlarmDriver: AlarmScheduling {
    private var ledger: RingLedger
    /// Schedules handed to AlarmKit whose call has not returned; kept in the ledger while they land.
    private var inFlight: Set<UUID> = []
    private let scheduleDelay: Duration?
    private let silent: Bool

    /// - Parameters:
    ///   - scheduleDelay: UI tests only (`-uitest-slow-schedule`): a pause before each schedule call.
    ///   - silent: UI tests only: alarms ring with the bundled silent sound (`LaunchOptions.silent`).
    init(ledger: RingLedger, scheduleDelay: Duration? = nil, silent: Bool) {
        self.ledger = ledger
        self.scheduleDelay = scheduleDelay
        self.silent = silent
    }

    private var manager: AlarmManager { .shared }

    func schedule(_ ring: Ring) async throws {
        // Write-ahead: the ring is known before AlarmKit can hold the alarm.
        ledger.record(ring)
        inFlight.insert(ring.id)
        defer { inFlight.remove(ring.id) }
        if let scheduleDelay { try? await Task.sleep(for: scheduleDelay) }
        _ = try await manager.schedule(id: ring.id, configuration: AlarmRequest.make(for: ring, silent: silent).configuration)
    }

    func cancel(_ id: UUID) {
        try? manager.stop(id: id)
        try? manager.cancel(id: id)
    }

    func stop(_ id: UUID) {
        try? manager.stop(id: id)
    }

    func table() -> [SystemAlarm] {
        do {
            let alarms = try manager.alarms
            ledger.prune(keeping: Set(alarms.map(\.id)).union(inFlight))
            return map(alarms)
        } catch {
            modelLog.error("Couldn't read AlarmKit's alarms: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated func alarmUpdates() -> AsyncStream<[SystemAlarm]> {
        AsyncStream { continuation in
            let task = Task {
                for await alarms in AlarmManager.shared.alarmUpdates {
                    continuation.yield(await self.map(alarms))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Rebuilds each alarm's ring from the ledger. Only a fresh `table()` read prunes the ledger: an update
    /// from `alarmUpdates` can be a snapshot taken before a schedule that has since landed.
    private func map(_ alarms: [Alarm]) -> [SystemAlarm] {
        alarms.map { alarm in
            ledger.systemAlarm(id: alarm.id, fireDate: Self.fireDate(alarm), alerting: alarm.state == .alerting)
        }
    }

    private static func fireDate(_ alarm: Alarm) -> Date? {
        if case let .fixed(date) = alarm.schedule { return date }
        return nil
    }
}

/// AlarmKit permission.
///
/// `AlarmManager.authorizationState` is a synchronous call to the alarm daemon. Right after the permission
/// prompt it has blocked for minutes (iOS 26.5 simulator, seen in the onboarding UI test), which froze the
/// whole app when it was read on the main thread. So it is only ever read off the main actor, and the
/// result of a request is used as it comes back.
enum AlarmAuthorization {
    static func state() async -> AlarmManager.AuthorizationState {
        await Task.detached { AlarmManager.shared.authorizationState }.value
    }

    /// Asks once if iOS has not asked yet, and returns the state the prompt left.
    static func request() async -> AlarmManager.AuthorizationState {
        if let state = try? await AlarmManager.shared.requestAuthorization() { return state }
        return await state()
    }

    static func watch(_ onChange: @escaping @MainActor (AlarmManager.AuthorizationState) -> Void) async {
        for await state in AlarmManager.shared.authorizationUpdates { await onChange(state) }
    }
}
