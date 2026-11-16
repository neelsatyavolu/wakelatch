import Foundation
import WakelatchCore

/// A fake AlarmKit table. Alarms alert when the clock passes their fire date and keep alerting until
/// they are stopped or cancelled. Pressing a button stops the alarm and returns what its `AlertSpec`
/// asks the app to do.
public struct FakeAlarmKit: Sendable {
    public struct Entry: Hashable, Sendable {
        public let ring: Ring
        public var alerting: Bool

        public init(ring: Ring, alerting: Bool) {
            self.ring = ring
            self.alerting = alerting
        }
    }

    /// One call the app made, in order.
    public enum Op: Hashable, Sendable {
        case schedule(UUID)
        case scheduleFailed(UUID)
        case cancel(UUID)
        case stop(UUID)
    }

    public struct ScheduleFailure: Error, Hashable, Sendable {
        public let id: UUID
    }

    public private(set) var table: [UUID: Entry]
    /// Alarms without Wakelatch metadata (scheduled by an older build). They never fire in the fake.
    public private(set) var foreign: [UUID: Date]
    /// Every schedule, failed schedule, cancel and stop, in order, for assertions.
    public private(set) var log: [Op]

    public init(table: [UUID: Entry] = [:]) {
        self.table = table
        self.foreign = [:]
        self.log = []
    }

    /// Ids alerting now.
    public var alerting: Set<UUID> {
        Set(table.values.lazy.filter(\.alerting).map(\.ring.id))
    }

    /// Every id AlarmKit holds, with or without metadata.
    public var ids: Set<UUID> {
        Set(table.keys).union(foreign.keys)
    }

    public func contains(_ id: UUID) -> Bool {
        table[id] != nil || foreign[id] != nil
    }

    /// The table as the app's driver would report it, oldest first.
    public var snapshot: [SystemAlarm] {
        let known = table.values.map {
            SystemAlarm(id: $0.ring.id, fireDate: $0.ring.date, ring: $0.ring, alerting: $0.alerting)
        }
        let other = foreign.map { SystemAlarm(id: $0.key, fireDate: $0.value, ring: nil, alerting: false) }
        return (known + other).sorted {
            ($0.fireDate ?? .distantPast, $0.id.uuidString) < ($1.fireDate ?? .distantPast, $1.id.uuidString)
        }
    }

    /// Adds or replaces an alarm (a replaced alarm stops alerting). Throws when `fails` contains its id.
    public mutating func schedule(_ ring: Ring, fails: Set<UUID> = []) throws {
        if fails.contains(ring.id) {
            log.append(.scheduleFailed(ring.id))
            throw ScheduleFailure(id: ring.id)
        }
        table[ring.id] = Entry(ring: ring, alerting: false)
        log.append(.schedule(ring.id))
    }

    /// Puts an alarm in the table without going through the app (a leftover from an earlier run).
    public mutating func insert(_ ring: Ring, alerting: Bool = false) {
        table[ring.id] = Entry(ring: ring, alerting: alerting)
    }

    /// Puts an alarm without Wakelatch metadata in the table.
    public mutating func insertForeign(id: UUID, fireDate: Date) {
        foreign[id] = fireDate
    }

    /// Removes an alarm (alerting or not). Unknown ids are ignored but still logged.
    public mutating func cancel(_ id: UUID) {
        table[id] = nil
        foreign[id] = nil
        log.append(.cancel(id))
    }

    /// Stops an alerting alarm; a fixed-date alarm then leaves the table. A silent alarm is left alone.
    public mutating func stop(_ id: UUID) {
        guard table[id]?.alerting == true else { return }
        table[id] = nil
        log.append(.stop(id))
    }

    /// The earliest fire date after `now` among alarms not yet alerting.
    public func nextFireDate(after now: Date) -> Date? {
        table.values.lazy.filter { !$0.alerting && $0.ring.date > now }.map(\.ring.date).min()
    }

    /// Moves the clock: every alarm whose fire date is at or before `now` starts alerting.
    /// Returns the ids that started alerting during this call.
    public mutating func advance(to now: Date) -> Set<UUID> {
        var started: Set<UUID> = []
        for (id, entry) in table where !entry.alerting && entry.ring.date <= now {
            table[id]?.alerting = true
            started.insert(id)
        }
        return started
    }

    /// Presses a button on an alerting alarm: stops it and returns `AlertSpec.for(kind).action(for:)`.
    /// Returns nil when the id is not alerting.
    public mutating func press(_ button: AlertButton, on id: UUID) -> AlertAction? {
        guard let entry = table[id], entry.alerting else { return nil }
        stop(id)
        return AlertSpec.for(entry.ring.kind).action(for: button)
    }

    /// Rings in the table, filtered by kind and morning, oldest first.
    public func live(kind: RingKind? = nil, morning: Date? = nil) -> [Ring] {
        table.values.lazy
            .map(\.ring)
            .filter { kind == nil || $0.kind == kind }
            .filter { morning == nil || $0.morning == morning }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
}
