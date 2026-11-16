import Foundation
import WakelatchCore

extension InvariantChecker {
    // MARK: INV5: after a solve, only that morning's awake checks remain

    /// At the solve itself: target holds exactly the planned awake checks (checks on) or nothing (checks off).
    func inv5AtSolve(_ step: SimStep, settings: EngineSettings) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for (morning, outcome) in step.after.finished where outcome == .solved && step.before.finished[morning] == nil {
            let rings = Oracle.rings(of: morning, in: step.after.target)
            let expected = settings.awakeChecks ? expectedChecks(solvedAt: step.now, timing: settings.timing) : []
            let actual = rings.map { Check(date: $0.date, group: $0.checkGroup, kind: $0.kind, level: $0.level) }
                .sorted(by: Check.order)
            if actual != expected {
                found.append(violation(.inv5, step, "target for solved \(morning) is \(actual.count) rings, expected \(expected.count) awake checks"))
            }
        }
        return found
    }

    /// Once reconcile settles: AlarmKit holds only target awake checks of each solved morning, and all future ones.
    func inv5Settled(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        let targetIDs = Set(step.after.target.map(\.id))
        for (morning, outcome) in step.after.finished where outcome == .solved {
            let held = step.system.live(morning: morning)
            if let stray = held.first(where: { $0.kind != .awakeCheck || !targetIDs.contains($0.id) }) {
                found.append(violation(.inv5, step, "solved \(morning) still holds \(stray.kind) at \(stray.date)"))
            }
            let missing = step.after.target.filter {
                $0.morning == morning && $0.date > step.now && !step.system.contains($0.id)
                    && !step.after.failedSchedule.contains($0.id)
            }
            if let first = missing.first {
                found.append(violation(.inv5, step, "awake check at \(first.date) of \(morning) not in AlarmKit"))
            }
        }
        return found
    }

    private struct Check: Equatable {
        let date: Date
        let group: Int?
        let kind: RingKind
        let level: Int

        static func order(_ a: Check, _ b: Check) -> Bool {
            (a.date, a.group ?? -1) < (b.date, b.group ?? -1)
        }
    }

    private func expectedChecks(solvedAt: Date, timing: PlanTiming) -> [Check] {
        timing.awakeOffsets.enumerated().flatMap { group, offset in
            (0...timing.awakeGuards).map { index in
                Check(date: solvedAt.addingTimeInterval(offset + Double(index) * timing.awakeGuardSpacing),
                      group: group, kind: .awakeCheck, level: 0)
            }
        }.sorted(by: Check.order)
    }

    // MARK: INV6: outcomes are final

    func inv6(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for (morning, outcome) in everFinished where step.after.finished[morning] != outcome {
            found.append(violation(.inv6, step, "finished[\(morning)] was \(outcome), now \(String(describing: step.after.finished[morning]))"))
        }
        var seen: Set<Date> = []
        for record in step.after.records {
            if !seen.insert(record.morning).inserted {
                found.append(violation(.inv6, step, "two records for \(record.morning)"))
            }
            if let earlier = everRecords[record.morning], earlier != record.outcome {
                found.append(violation(.inv6, step, "record for \(record.morning) went from \(earlier) to \(record.outcome)"))
            }
            if let outcome = step.after.finished[record.morning], outcome != record.outcome {
                found.append(violation(.inv6, step, "record \(record.outcome) disagrees with finished \(outcome)"))
            }
        }
        return found
    }

    // MARK: INV7, INV8: a landed pass leaves nothing to do and nothing unknown

    func inv7and8(_ step: SimStep, grace: TimeInterval) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        if step.after.failedSchedule.isEmpty {
            let active = Oracle.activeMorning(in: step.after, at: step.now, grace: grace)
            let plan = Reconciler.plan(target: step.after.target, system: step.system.snapshot,
                                       pending: step.after.pendingSchedule, activeMorning: active, now: step.now)
            if !plan.isEmpty {
                found.append(violation(.inv7, step,
                    "second pass not empty: adopt \(plan.adopt.count), schedule \(plan.schedule.count), cancel \(plan.cancel.count)"))
            }
        }
        let targetIDs = Set(step.after.target.map(\.id))
        let unknown = step.system.ids.subtracting(targetIDs)
        if !unknown.isEmpty {
            found.append(violation(.inv8, step, "\(unknown.count) alarms in AlarmKit are not in target"))
        }
        return found
    }

    // MARK: INV9: sheets are dismissed before the cover; never silence behind a hidden cover

    func inv9(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        let silenceIndex = step.effects.firstIndex { $0.silencedID != nil }
        if case .foreground(.sheet) = step.processBefore, step.screenBefore == .none, step.screen != .none {
            let dismissIndex = step.effects.firstIndex(of: .dismissHomeSheets)
            if dismissIndex == nil {
                found.append(violation(.inv9, step, "screen \(step.screen) over an open sheet without dismissHomeSheets"))
            } else if let silence = silenceIndex, let dismiss = dismissIndex, silence < dismiss {
                found.append(violation(.inv9, step, "silence before dismissHomeSheets"))
            }
        }
        if !step.coverVisible, silenceIndex != nil {
            found.append(violation(.inv9, step, "silence while the cover is hidden"))
        }
        return found
    }

    // MARK: INV10: two skips per Gregorian month (in the calendar's time zone, whatever its system)

    func inv10(_ step: SimStep, calendar: Calendar) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        let gregorian = SkipLedger.monthCalendar(calendar)
        let months = Dictionary(grouping: step.after.skips.used) {
            gregorian.dateComponents([.year, .month], from: $0)
        }
        for (month, uses) in months where uses.count > SkipLedger.perMonth {
            found.append(violation(.inv10, step, "\(uses.count) skips in \(month.year ?? 0)-\(month.month ?? 0)"))
        }
        if case .skip? = step.event, step.before.skips.remaining(at: step.now, calendar: calendar) == 0,
           step.after.finished != step.before.finished || step.after.skips != step.before.skips {
            found.append(violation(.inv10, step, "a skip with none left was accepted"))
        }
        return found
    }
}
