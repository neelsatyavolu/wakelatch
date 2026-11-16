import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract R2, R3, R6 on the pure `Reconciler` (S09-S11, S14, S15 at the planning level).
@Suite("R: Reconciler.plan")
struct ReconcilerTests {
    let now = Std.t(6, 45)
    let tomorrow = Std.ideal(day: 17)

    func table(_ rings: [Ring], alerting: Set<UUID> = []) -> [SystemAlarm] {
        rings.map { SystemAlarm(id: $0.id, fireDate: $0.date, ring: $0, alerting: alerting.contains($0.id)) }
    }

    /// Awake checks of an earlier solved morning that are still ahead at 06:45 (a contrived but valid target).
    var checks: [Ring] { Std.awakeChecks(solvedAt: Std.t(6, 42), of: Std.ideal(day: 15)) }

    @Test("S10 (R2.3): active deadline and guards first, then its other latched rings, then awake checks, then the rest, each by date")
    func scheduleOrder() {
        let target = Std.morning() + checks + Std.morning(tomorrow)
        let plan = Reconciler.plan(target: target, system: [], pending: [], activeMorning: Std.today, now: now)
        let expected = [Std.deadline()] + Std.guards() + [Std.snooze(0), Std.snooze(1), Std.snooze(2)]
            + checks.sorted { $0.date < $1.date } + Std.morning(tomorrow)
        #expect(plan.schedule == expected)
        #expect(plan.adopt.isEmpty)
        #expect(plan.cancel.isEmpty)
    }

    @Test("R3: rings at or before now are never scheduled")
    func pastNeverScheduled() {
        let plan = Reconciler.plan(target: Std.morning(), system: [], pending: [], activeMorning: Std.today, now: Std.t(7, 10))
        #expect(!plan.schedule.contains { $0.date <= Std.t(7, 10) })
        #expect(plan.schedule.first == Std.guardRing(1))
        #expect(plan.schedule.count == 60)
    }

    @Test("S11 (R2): effects are persist, the active morning's schedules, the cancels, then other mornings' schedules")
    func effectOrder() {
        let orphan = Std.guardRing(3, of: Std.ideal(day: 18))
        let target = Std.morning(tomorrow)
        let plan = Reconciler.plan(target: target, system: table([orphan]), pending: [], activeMorning: nil, now: now)
        #expect(plan.cancel == [orphan.id])
        #expect(plan.scheduleFirst == 0)
        #expect(plan.effects == [.persist, .cancel(orphan.id)] + target.map { .schedule($0) })
        let active = Reconciler.plan(target: Std.morning() + target, system: table([orphan]), pending: [],
                                     activeMorning: Std.today, now: Std.t(6, 45))
        let urgent = [Std.deadline()] + Std.guards() + [Std.snooze(0), Std.snooze(1), Std.snooze(2)]
        #expect(active.scheduleFirst == urgent.count)
        #expect(active.effects == [.persist] + urgent.map { .schedule($0) } + [.cancel(orphan.id)]
            + target.map { .schedule($0) })
    }

    @Test("R2: a plan that only cancels does not persist")
    func cancelOnly() {
        let orphan = Std.guardRing(3, of: Std.ideal(day: 18))
        let plan = Reconciler.plan(target: [], system: table([orphan]), pending: [], activeMorning: nil, now: now)
        #expect(plan.effects == [.cancel(orphan.id)])
    }

    @Test("R6 (S09): target already in AlarmKit gives an empty plan and no effects")
    func nothingToDo() {
        let target = Std.morning(tomorrow)
        let plan = Reconciler.plan(target: target, system: table(target), pending: [], activeMorning: nil, now: now)
        #expect(plan.isEmpty)
        #expect(plan.effects.isEmpty)
    }

    @Test("R2.3, R2.4: pending ids are neither scheduled again nor cancelled")
    func pendingRespected() {
        let target = Std.morning(tomorrow)
        let pending = Set(target.prefix(10).map(\.id))
        let stray = Std.main(of: Std.ideal(day: 19))
        let plan = Reconciler.plan(target: target, system: table([stray]), pending: pending.union([stray.id]),
                                   activeMorning: nil, now: now)
        #expect(plan.schedule == Array(target.dropFirst(10)))
        #expect(plan.cancel.isEmpty)
    }

    @Test("an alerting alarm that is in target is kept")
    func alertingKept() {
        let target = Std.morning()
        let system = table(target.filter { $0.date <= now }, alerting: [Std.main().id])
            + table(target.filter { $0.date > now })
        let plan = Reconciler.plan(target: target, system: system, pending: [], activeMorning: Std.today, now: now)
        #expect(plan.isEmpty)
    }

    @Test("S14 (R2.1): an unknown future latched alarm of the active morning is adopted, not cancelled")
    func adoptActive() {
        let extra = Ring(date: Std.t(7, 30, 30), kind: .guardRing, level: 3, morning: Std.today, challenge: .math)
        let target = Std.morning()
        let plan = Reconciler.plan(target: target, system: table(target.filter { $0.date > now } + [extra]),
                                   pending: [], activeMorning: Std.today, now: now)
        #expect(plan.adopt == [extra])
        #expect(plan.cancel.isEmpty)
        #expect(plan.schedule.isEmpty)
        #expect(plan.effects == [.persist])
    }

    @Test("S15: unknown alarms are cancelled when they are past, not latched, of another morning, or without metadata")
    func orphansCancelled() {
        let past = Ring(date: Std.t(6, 44), kind: .snooze, level: 1, morning: Std.today, challenge: .math)
        let check = Std.awake(group: 0, index: 0, solvedAt: Std.t(6, 43), of: Std.today)
        let otherMorning = Std.guardRing(2, of: Std.ideal(day: 15))
        let foreign = SystemAlarm(id: UUID(), fireDate: Std.t(7, 0), ring: nil, alerting: false)
        let plan = Reconciler.plan(target: [], system: table([past, check, otherMorning]) + [foreign],
                                   pending: [], activeMorning: Std.today, now: now)
        #expect(plan.adopt.isEmpty)
        #expect(Set(plan.cancel) == [past.id, check.id, otherMorning.id, foreign.id])
    }

    @Test("with no active morning nothing is adopted")
    func noAdoptWithoutActiveMorning() {
        let extra = Std.guardRing(5, of: tomorrow)
        let plan = Reconciler.plan(target: [], system: table([extra]), pending: [], activeMorning: nil, now: now)
        #expect(plan.adopt.isEmpty)
        #expect(plan.cancel == [extra.id])
    }

    @Test("INV7: planning again after the plan landed is empty")
    func idempotent() {
        let target = Std.morning() + Std.morning(tomorrow)
        let orphan = Std.main(of: Std.ideal(day: 20))
        let first = Reconciler.plan(target: target, system: table([orphan]), pending: [], activeMorning: Std.today, now: now)
        var held = [orphan]
        held += first.schedule
        held.removeAll { first.cancel.contains($0.id) }
        let second = Reconciler.plan(target: target + first.adopt, system: table(held), pending: [],
                                     activeMorning: Std.today, now: now)
        #expect(!first.isEmpty)
        #expect(second.isEmpty)
    }
}
