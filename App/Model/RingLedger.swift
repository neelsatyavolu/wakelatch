import Foundation
import WakelatchCore

/// The ring behind every alarm Wakelatch handed to AlarmKit. AlarmKit's `Alarm` does not return the
/// metadata it was scheduled with, so this file is how a table read rebuilds `SystemAlarm.ring` (contract I3),
/// which reconcile needs to adopt a morning under way after the engine state was lost (R2).
/// A ring is recorded before the schedule call, so an alarm AlarmKit holds always has its ring here.
struct RingLedger {
    let url: URL?
    private(set) var rings: [UUID: Ring]

    /// Loads the ledger at `url`; nil keeps it in memory only.
    init(url: URL?, rings: [UUID: Ring] = [:]) {
        self.url = url
        let saved = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([UUID: Ring].self, from: $0) }
        self.rings = (saved ?? [:]).merging(rings) { _, new in new }
        if !rings.isEmpty { save() }
    }

    mutating func record(_ ring: Ring) {
        guard rings[ring.id] != ring else { return }
        rings[ring.id] = ring
        save()
    }

    /// Keeps only the ids in `ids` (AlarmKit's table plus schedules in flight).
    mutating func prune(keeping ids: Set<UUID>) {
        let kept = rings.filter { ids.contains($0.key) }
        guard kept.count != rings.count else { return }
        rings = kept
        save()
    }

    func systemAlarm(id: UUID, fireDate: Date?, alerting: Bool) -> SystemAlarm {
        SystemAlarm(id: id, fireDate: fireDate, ring: rings[id], alerting: alerting)
    }

    private func save() {
        guard let url else { return }
        do {
            try FileStorage.write(rings, to: url)
        } catch {
            modelLog.error("Alarm ledger not saved: \(error.localizedDescription)")
        }
    }
}
