import Foundation
import WakelatchCore

/// The checker's own memory of every morning it has seen under way, so a morning the engine drops from its
/// target (or ends early) is still held to INV2, INV3 and INV11. Nothing here reads the engine's queries.
extension InvariantChecker {
    /// Remembers the active morning of `state` (its end and latched rings), and adds rings that later join
    /// a remembered morning that is not finished (adoption, guard top-up). `endsBy` only ever grows.
    mutating func learn(_ state: EngineState, at now: Date, grace: TimeInterval) {
        if let active = Oracle.activeMorning(in: state, at: now, grace: grace), underWay[active] == nil {
            underWay[active] = .distantPast
        }
        for morning in underWay.keys where state.finished[morning] == nil {
            let rings = state.target.filter { $0.morning == morning && $0.latched }
            for ring in rings { chain[morning, default: [:]][ring.id] = ring }
            if let end = Oracle.endsBy(of: morning, in: state.target, grace: grace) {
                underWay[morning] = max(underWay[morning] ?? end, end)
            }
        }
    }

    /// Remembered mornings that are not finished in `state` and not past their end at `now`.
    func openMornings(_ state: EngineState, at now: Date) -> [Date] {
        underWay.filter { state.finished[$0.key] == nil && now <= $0.value }.keys.sorted()
    }

    // MARK: INV2: every future latched ring of a morning under way is held or in flight

    func inv2(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for morning in openMornings(step.after, at: step.now) {
            let current = step.after.target.filter { $0.morning == morning && $0.latched }
            let rings = Array((chain[morning] ?? [:]).values) + current
            let missing = rings.filter {
                $0.date > step.now && !step.system.contains($0.id) && !step.inFlight.contains($0.id)
                    && !step.after.failedSchedule.contains($0.id)
            }
            let unique = Set(missing.map(\.id))
            if let first = missing.min(by: { $0.date < $1.date }) {
                found.append(violation(.inv2, step,
                    "\(unique.count) future latched rings of \(morning) missing from AlarmKit, first \(first.kind) at \(first.date)"))
            }
        }
        return found
    }

    // MARK: INV3: a morning under way keeps its chain until it is finished

    /// A latched ring the target held while its morning was under way leaves neither AlarmKit nor target
    /// before the morning is finished (by solve, skip or the missed timeout, which INV4 and INV11 check).
    /// Rings that were never in target (stale leftovers) may be cancelled.
    func inv3(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for morning in openMornings(step.after, at: step.now) {
            for ring in (chain[morning] ?? [:]).values where ring.date > step.now {
                if step.systemBefore.contains(ring.id) && !step.system.contains(ring.id) {
                    found.append(violation(.inv3, step,
                        "\(ring.kind) at \(ring.date) of unfinished \(morning) left AlarmKit"))
                }
                if step.before.target.contains(where: { $0.id == ring.id })
                    && !step.after.target.contains(where: { $0.id == ring.id }) {
                    found.append(violation(.inv3, step,
                        "\(ring.kind) at \(ring.date) of unfinished \(morning) left target"))
                }
            }
        }
        return found
    }

    // MARK: INV11: a morning ends as missed only after its end, and as skipped only through K1

    func inv11(_ step: SimStep, grace: TimeInterval, calendar: Calendar) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for (morning, outcome) in step.after.finished where step.before.finished[morning] == nil {
            let problem: String?
            switch outcome {
            case .missed: problem = missedProblem(step, morning: morning, grace: grace)
            case .skipped: problem = skippedProblem(step, morning: morning, calendar: calendar)
            case .solved: problem = nil
            }
            if let problem { found.append(violation(.inv11, step, "\(morning) \(outcome) but \(problem)")) }
        }
        return found
    }

    private func missedProblem(_ step: SimStep, morning: Date, grace: TimeInterval) -> String? {
        let ends = [Oracle.endsBy(of: morning, in: step.before.target, grace: grace), underWay[morning]]
            .compactMap { $0 }.max()
        guard let ends else { return "it had no latched ring" }
        return step.now > ends ? nil : "its last latched ring plus grace is \(ends)"
    }

    private func skippedProblem(_ step: SimStep, morning: Date, calendar: Calendar) -> String? {
        guard case .skip(let id, _)? = step.event else { return "the event was not skip" }
        let inTarget = step.before.target.contains { $0.id == id && $0.morning == morning }
        let open = step.before.challenge.map { $0.ring.id == id && $0.morning == morning } ?? false
        guard inTarget || open else { return "ring \(id) is not one of its rings" }
        return step.before.skips.remaining(at: step.now, calendar: calendar) > 0 ? nil : "no skip was left"
    }

    // MARK: INV12: the schedule budget, and every guard on the next morning and the one under way (D2)

    func inv12(_ step: SimStep, settings: EngineSettings, grace: TimeInterval) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        let future = step.after.target.filter { $0.date > step.now }.count
        if future > ScheduleBudget.limit {
            found.append(violation(.inv12, step, "\(future) future rings in target, over \(ScheduleBudget.limit)"))
        }
        let guardCount = settings.timing.guardCount
        guard guardCount > 0 else { return found }
        let guards = { (morning: Date) in
            step.after.target.filter { $0.morning == morning && $0.kind == .guardRing }.count
        }
        if let next = nextMorning(step.after, at: step.now), guards(next) != guardCount {
            found.append(violation(.inv12, step, "next morning \(next) holds \(guards(next)) of \(guardCount) guards"))
        }
        if let active = Oracle.activeMorning(in: step.after, at: step.now, grace: grace),
           step.after.target.contains(where: { $0.morning == active && $0.kind == .deadline }),
           guards(active) < guardCount {
            found.append(violation(.inv12, step, "morning under way \(active) holds \(guards(active)) of \(guardCount) guards"))
        }
        return found
    }

    /// The nearest unfinished morning in target that has not started (neither its first ring nor its Ideal due).
    private func nextMorning(_ state: EngineState, at now: Date) -> Date? {
        var first: [Date: Date] = [:]
        for ring in state.target where ring.kind != .awakeCheck {
            first[ring.morning] = min(first[ring.morning] ?? ring.date, ring.date)
        }
        return first.filter { state.finished[$0.key] == nil && min($0.value, $0.key) > now }.keys.min()
    }
}
