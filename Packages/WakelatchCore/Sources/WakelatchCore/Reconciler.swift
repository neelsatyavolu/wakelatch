import Foundation

/// One reconcile pass: how to bring AlarmKit's table to `target`.
public struct ReconcilePlan: Hashable, Sendable {
    /// System alarms not in `target` that belong to the active morning; the engine adds them to `target`.
    public let adopt: [Ring]
    /// Future rings missing from the system and not pending, in priority order.
    public let schedule: [Ring]
    /// How many leading `schedule` rings go out before any cancel: the active morning's latched rings and
    /// awake checks.
    public let scheduleFirst: Int
    /// How many `schedule` rings after those belong to the nearest morning that has not started. They go out
    /// after the cancels of later mornings and before the cancels of the alarms they replace, so a kill in
    /// the middle of a time change never leaves that morning with no alarm.
    public let scheduleNext: Int
    /// System alarm ids that are neither in `target`, adopted, nor pending.
    public let cancel: [UUID]
    /// How many leading `cancel` ids go out before the nearest morning's schedules.
    public let cancelFirst: Int

    public init(adopt: [Ring], schedule: [Ring], scheduleFirst: Int = 0, scheduleNext: Int = 0, cancel: [UUID],
                cancelFirst: Int? = nil) {
        self.adopt = adopt
        self.schedule = schedule
        self.scheduleFirst = min(max(0, scheduleFirst), schedule.count)
        self.scheduleNext = min(max(0, scheduleNext), schedule.count - self.scheduleFirst)
        self.cancel = cancel
        self.cancelFirst = min(max(0, cancelFirst ?? cancel.count), cancel.count)
    }

    public var isEmpty: Bool { adopt.isEmpty && schedule.isEmpty && cancel.isEmpty }

    public var firstSchedules: ArraySlice<Ring> { schedule.prefix(scheduleFirst) }
    public var firstCancels: ArraySlice<UUID> { cancel.prefix(cancelFirst) }
    public var nextSchedules: ArraySlice<Ring> { schedule.dropFirst(scheduleFirst).prefix(scheduleNext) }
    public var lateCancels: ArraySlice<UUID> { cancel.dropFirst(cancelFirst) }
    public var lateSchedules: ArraySlice<Ring> { schedule.dropFirst(scheduleFirst + scheduleNext) }

    /// `.persist` (when anything is scheduled or adopted), then the first schedules, the first cancels, the
    /// nearest morning's schedules, the remaining cancels and the remaining schedules.
    public var effects: [Effect] {
        let persist: [Effect] = adopt.isEmpty && schedule.isEmpty ? [] : [.persist]
        return persist + firstSchedules.map(Effect.schedule) + firstCancels.map(Effect.cancel)
            + nextSchedules.map(Effect.schedule) + lateCancels.map(Effect.cancel)
            + lateSchedules.map(Effect.schedule)
    }
}

/// Diffs the engine's target against AlarmKit. Pure; the engine applies `adopt` and `pendingSchedule`.
public enum Reconciler {
    /// - schedule: rings in `target` with `date > now`, not in `system`, not in `pending`. Order: the active
    ///   morning's deadline and guards by date, then its other latched rings by date, then awake checks by date
    ///   (these `scheduleFirst` go out before the cancels), then every other ring by date.
    /// - adopt: system alarms whose id is not in `target`, whose `ring` is latched, belongs to `activeMorning`,
    ///   fires after `now`, is not an old version of a target ring (same kind and date), and does not lower the
    ///   bar: no latched ring of that morning (in target or the table) dated earlier has a higher level, so a
    ///   stale snooze after the Deadline is never adopted. When target holds the morning's deadline, only
    ///   guards after it and no later than target's last latched ring qualify (no second plan is adopted).
    /// - cancel: system alarms whose id is not in `target`, not adopted and not in `pending`. Those of another
    ///   morning than the active one that fire by the end of the nearest morning still to come are put last
    ///   (`cancelFirst`), after that morning's new rings (`scheduleNext`): an evening time change never leaves
    ///   tomorrow with no alarm if the app is killed in the middle.
    /// Running it again after its schedules and cancels landed yields an empty plan (INV7).
    public static func plan(target: [Ring], system: [SystemAlarm], pending: Set<UUID>,
                            activeMorning: Date?, now: Date) -> ReconcilePlan {
        let targetIDs = Set(target.map(\.id))
        let systemIDs = Set(system.map(\.id))
        let unknown = system.filter { !targetIDs.contains($0.id) }
        let reference = target + system.compactMap(\.ring)
        let own = target.filter { $0.morning == activeMorning }
        let slots = Set(own.map { Slot(kind: $0.kind, date: $0.date) })
        let adopt = unknown
            .filter { alarm in alarm.ring.map { !slots.contains(Slot(kind: $0.kind, date: $0.date)) } ?? false }
            .filter { alarm in alarm.ring.map { fitsPlan($0, own: own) } ?? false }
            .compactMap { adoptable($0, activeMorning: activeMorning, reference: reference, now: now) }
        let adoptedIDs = Set(adopt.map(\.id))
        let schedule = target
            .filter { $0.date > now && !systemIDs.contains($0.id) && !pending.contains($0.id) }
            .sorted { order($0, activeMorning) < order($1, activeMorning) }
        let first = schedule.prefix { order($0, activeMorning).group < Self.otherGroup }.count
        let nearest = schedule.dropFirst(first).filter { $0.kind != .awakeCheck }.map(\.morning).min()
        // By date, the other mornings' rings come one morning after another, so the nearest one leads.
        let next = schedule.dropFirst(first).prefix { $0.morning == nearest }.count
        let nearestEnd = nearest.flatMap { day in target.filter { $0.morning == day }.map(\.date).max() }
        let stale = unknown.filter { !adoptedIDs.contains($0.id) && !pending.contains($0.id) }
        // Old alarms that would ring by the end of the nearest morning are cancelled only after its new rings.
        let replaced = stale.filter { alarm in
            guard next > 0, let nearestEnd, let ring = alarm.ring, ring.morning != activeMorning else { return false }
            let date = alarm.fireDate ?? ring.date
            return date > now && date <= nearestEnd
        }.map(\.id)
        let early = stale.map(\.id).filter { !replaced.contains($0) }
        return ReconcilePlan(adopt: adopt, schedule: schedule, scheduleFirst: first, scheduleNext: next,
                             cancel: early + replaced, cancelFirst: early.count)
    }

    /// The morning under way that only AlarmKit still knows about, for a pass whose target has no active
    /// morning (state lost or reset mid-morning): the oldest morning of a latched alarm with metadata that has
    /// no ring in `target`, is not in `finished`, has started (`morning - lead <= now`), is no older than
    /// `maxSpan` (the longest a morning can last), and whose last latched alarm plus grace is not yet past.
    public static func orphanMorning(in system: [SystemAlarm], target: [Ring], finished: [Date: Outcome],
                                     now: Date, lead: TimeInterval, grace: TimeInterval,
                                     maxSpan: TimeInterval) -> Date? {
        let known = Set(target.map(\.morning))
        var last: [Date: Date] = [:]
        for alarm in system {
            guard let ring = alarm.ring, ring.latched, !known.contains(ring.morning) else { continue }
            let date = alarm.fireDate ?? ring.date
            last[ring.morning] = max(last[ring.morning] ?? date, date)
        }
        return last.filter { morning, end in
            finished[morning] == nil && morning.addingTimeInterval(-lead) <= now
                && now <= min(end.addingTimeInterval(grace), morning.addingTimeInterval(maxSpan))
        }.keys.min()
    }

    /// With the morning's deadline in target, only a guard after it and within target's last latched ring.
    private static func fitsPlan(_ ring: Ring, own: [Ring]) -> Bool {
        guard let deadline = own.first(where: { $0.kind == .deadline }) else { return true }
        let last = own.filter(\.latched).map(\.date).max() ?? deadline.date
        return ring.kind == .guardRing && ring.date > deadline.date && ring.date <= last
    }

    private static func adoptable(_ alarm: SystemAlarm, activeMorning: Date?, reference: [Ring],
                                  now: Date) -> Ring? {
        guard let ring = alarm.ring, ring.latched, let activeMorning, ring.morning == activeMorning,
              (alarm.fireDate ?? ring.date) > now else { return nil }
        let lowersBar = reference.contains {
            $0.morning == ring.morning && $0.latched && $0.date < ring.date && $0.level > ring.level
        }
        guard !lowersBar else { return nil }
        return Ring(id: alarm.id, date: ring.date, kind: ring.kind, level: ring.level, morning: ring.morning,
                    checkGroup: ring.checkGroup, challenge: ring.challenge)
    }

    private static let otherGroup = 3

    private struct Slot: Hashable {
        let kind: RingKind
        let date: Date
    }

    private struct Order: Comparable {
        let group: Int
        let date: Date
        let id: String

        static func < (a: Order, b: Order) -> Bool { (a.group, a.date, a.id) < (b.group, b.date, b.id) }
    }

    private static func order(_ ring: Ring, _ active: Date?) -> Order {
        let isActive = active != nil && ring.morning == active
        let group: Int
        switch ring.kind {
        case .deadline, .guardRing: group = isActive ? 0 : otherGroup
        case .main, .snooze: group = isActive ? 1 : otherGroup
        case .awakeCheck: group = 2
        case .nudge: group = otherGroup
        }
        return Order(group: group, date: ring.date, id: ring.id.uuidString)
    }
}
