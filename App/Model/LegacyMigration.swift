import Foundation
import WakelatchCore

/// Carries what builds before the morning engine kept in UserDefaults into the engine state, once:
/// history, the month's emergency skips (so an update never hands out fresh skips), and the rings of
/// alarms already in AlarmKit (so a morning under way when the update lands can be adopted, rule R2).
/// A morning under way at the update also goes straight into target, past rings included, so the first
/// event already treats it as active: "I'm up" or Stop on one of its alerts opens the challenge (S1).
enum LegacyMigration {
    struct Result {
        let state: EngineState
        let ledger: [UUID: Ring]
    }

    /// Nil when there is nothing to carry over.
    static func run(_ storage: Storage, now: Date = .now) -> Result? {
        let records = storage.load([LegacyRecord].self, key: "records") ?? []
        let skips = storage.load(SkipLedger.self, key: "skips")
        let rings = storage.load([LegacyRing].self, key: "rings") ?? []
        storage.remove(Storage.legacyKeys)
        guard !records.isEmpty || skips != nil || !rings.isEmpty else { return nil }
        let converted = records.map(\.record).suffix(EngineState.recordLimit)
        let finished = Dictionary(converted.map { ($0.morning, $0.outcome) }) { first, _ in first }
        let carried = rings.compactMap(\.ring)
        let state = EngineState(target: underWay(carried, finished: finished, now: now), finished: finished,
                                records: Array(converted), skips: skips ?? SkipLedger())
        let ledger = Dictionary(carried.map { ($0.id, $0) }) { first, _ in first }
        return Result(state: state, ledger: ledger)
    }

    /// The latched rings of the oldest legacy morning that has started, is not finished, and whose last
    /// latched ring plus grace is not past.
    static func underWay(_ rings: [Ring], finished: [Date: Outcome], now: Date) -> [Ring] {
        let grace = PlanTiming.production(PlanOptions()).grace
        let mornings = Dictionary(grouping: rings.filter(\.latched), by: \.morning).filter { morning, own in
            let last = own.map(\.date).max() ?? .distantPast
            return finished[morning] == nil && own.contains { $0.date <= now } && now <= last.addingTimeInterval(grace)
        }
        guard let oldest = mornings.keys.min(), let own = mornings[oldest] else { return [] }
        return own.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
}

/// `MorningRecord` as builds before 1.1 stored it.
private struct LegacyRecord: Decodable {
    let morning: Date
    let deadline: Date
    let upAt: Date?
    let skipped: Bool?

    var record: MorningRecord {
        let outcome: Outcome = skipped == true ? .skipped : (upAt == nil ? .missed : .solved)
        return MorningRecord(morning: morning, deadline: deadline, outcome: outcome,
                             upAt: outcome == .solved ? upAt : nil)
    }
}

/// `ScheduledRing` as builds before 1.1 stored it. Its id is the random id the alarm has in AlarmKit.
private struct LegacyRing: Decodable {
    let id: UUID
    let date: Date
    let kind: String
    let level: Int
    let morning: Date
    let checkGroup: Int?

    var ring: Ring? {
        RingKind(rawValue: kind).map {
            Ring(id: id, date: date, kind: $0, level: level, morning: morning, checkGroup: checkGroup)
        }
    }
}
