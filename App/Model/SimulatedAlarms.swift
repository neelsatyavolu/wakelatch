import Foundation
import WakelatchCore

/// Stands in for AlarmKit in UI tests on the simulator (`-uitest-simulated-alarms`), so a whole morning can
/// ring there without a sound.
///
/// Why: in the iOS 26.5 simulator a real AlarmKit alarm either plays the system alarm tone out loud, or, with
/// any custom sound (even a silent file), crashes SpringBoard's tone player when it fires
/// (`TLAlertQueuePlayerController`). So the simulator cannot ring a real alarm silently.
///
/// It behaves like AlarmKit's fixed one-shot alarms as Wakelatch uses them: an alarm alerts from its date
/// until it is stopped or cancelled, and then leaves the table. The table is saved to a file, so it outlives
/// the process the way AlarmKit's does. It has no system alert and no alert buttons.
actor SimulatedAlarms: AlarmScheduling {
    private let url: URL
    private let scheduleDelay: Duration?
    private let now: @Sendable () -> Date
    private var rings: [UUID: Ring]

    /// How often `alarmUpdates` looks for an alarm that started alerting.
    static let pollInterval: Duration = .milliseconds(250)

    /// - Parameters:
    ///   - url: where the table is kept between launches.
    ///   - scheduleDelay: `-uitest-slow-schedule`, a pause before each schedule lands.
    init(url: URL, scheduleDelay: Duration? = nil, now: @escaping @Sendable () -> Date = { .now }) {
        self.url = url
        self.scheduleDelay = scheduleDelay
        self.now = now
        rings = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([UUID: Ring].self, from: $0) } ?? [:]
    }

    func schedule(_ ring: Ring) async throws {
        if let scheduleDelay { try? await Task.sleep(for: scheduleDelay) }
        replace(rings.merging([ring.id: ring]) { _, new in new })
    }

    func cancel(_ id: UUID) {
        replace(rings.filter { $0.key != id })
    }

    /// Stopping an alarm that is alerting ends it, as with a one-shot AlarmKit alarm. A later alarm is kept.
    func stop(_ id: UUID) {
        guard let ring = rings[id], ring.date <= now() else { return }
        cancel(id)
    }

    func table() -> [SystemAlarm] {
        let time = now()
        return rings.values.sorted { $0.date < $1.date }.map { ring in
            SystemAlarm(id: ring.id, fireDate: ring.date, ring: ring, alerting: ring.date <= time)
        }
    }

    /// The table now, then again whenever an alarm is added, removed, or starts alerting.
    nonisolated func alarmUpdates() -> AsyncStream<[SystemAlarm]> {
        AsyncStream { continuation in
            let task = Task {
                var last: [SystemAlarm]?
                while !Task.isCancelled {
                    let current = await self.table()
                    if current != last {
                        continuation.yield(current)
                        last = current
                    }
                    try? await Task.sleep(for: Self.pollInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func replace(_ next: [UUID: Ring]) {
        rings = next
        do {
            try FileStorage.write(next, to: url)
        } catch {
            modelLog.error("Simulated alarms not saved: \(error.localizedDescription)")
        }
    }
}
