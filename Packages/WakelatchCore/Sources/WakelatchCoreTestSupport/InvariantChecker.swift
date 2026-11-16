import Foundation
import WakelatchCore

/// Checks INV1-INV10 after every step. Keeps the history the transition invariants need.
/// Definitions come from `Oracle` (the contract), never from the engine's own queries.
public struct InvariantChecker: Sendable {
    /// The first `storedLimit` violations, in order.
    public private(set) var violations: [InvariantViolation]
    /// Every violation found, including those past `storedLimit`.
    public private(set) var violationCount: Int

    static let storedLimit = 200

    /// Every outcome ever observed, by morning (INV6).
    var everFinished: [Date: Outcome] = [:]
    var everRecords: [Date: Outcome] = [:]
    /// Kinds marked unavailable while a challenge of that morning was open (C4, INV4).
    var unavailable: [Date: Set<ChallengeKind>] = [:]
    /// Every morning seen under way, with the latest end (last latched ring plus grace) observed (INV2, INV3).
    var underWay: [Date: Date] = [:]
    /// The latched rings each remembered morning's target held while it was under way, by id (INV2, INV3).
    var chain: [Date: [UUID: Ring]] = [:]
    /// Quiescent steps where a fresh pass had settled, so INV5, INV7 and INV8 really ran.
    public private(set) var settledSteps = 0

    public init() {
        violations = []
        violationCount = 0
    }

    /// Checks one step against every invariant; returns the new violations and keeps them.
    @discardableResult
    public mutating func observe(_ step: SimStep, settings: EngineSettings, calendar: Calendar)
        -> [InvariantViolation] {
        let grace = settings.timing.grace
        learn(step.before, at: step.now, grace: grace)
        var found: [InvariantViolation] = []
        found += inv1(step, grace: grace)
        if step.quiescent {
            found += inv2(step)
            found += inv13(step, settings: settings)
        }
        if step.event != nil {
            found += inv3(step)
            found += inv4(step)
            found += inv5AtSolve(step, settings: settings)
            found += inv9(step)
            found += inv10(step, calendar: calendar)
            found += inv11(step, grace: grace, calendar: calendar)
            found += inv12(step, settings: settings, grace: grace)
        }
        found += inv6(step)
        if step.reconcileSettled {
            settledSteps += 1
            found += inv5Settled(step)
            found += inv7and8(step, grace: grace)
        }
        remember(step)
        learn(step.after, at: step.now, grace: grace)
        violationCount += found.count
        violations += found.prefix(max(0, Self.storedLimit - violations.count))
        return found
    }

    func violation(_ invariant: Invariant, _ step: SimStep, _ detail: String) -> InvariantViolation {
        let event = step.event.map { "\($0)" } ?? "quiescent"
        return InvariantViolation(invariant: invariant, at: step.now, detail: "\(detail) [after \(event)]")
    }

    private mutating func remember(_ step: SimStep) {
        for (morning, outcome) in step.after.finished where everFinished[morning] == nil {
            everFinished[morning] = outcome
        }
        for record in step.after.records where everRecords[record.morning] == nil {
            everRecords[record.morning] = record.outcome
        }
        if case .challengeUnavailable(let kind, _)? = step.event, let open = step.before.challenge, open.kind == kind {
            unavailable[open.morning, default: []].insert(kind)
        }
    }

    // MARK: INV1: the foreground shows the active morning's due ring

    func inv1(_ step: SimStep, grace: TimeInterval) -> [InvariantViolation] {
        guard step.isForeground,
              let morning = Oracle.activeMorning(in: step.after, at: step.now, grace: grace),
              let due = Oracle.latestDueLatched(in: step.after.target, morning: morning, at: step.now)
        else { return [] }
        switch step.screen {
        case .ringing(let ring, _, _) where ring.id == due.id:
            return []
        case .challenge(let open) where open.morning == morning && open.level >= due.level:
            return []
        case .awakeCheck:
            return []   // S3 outranks S4.
        case .none where step.session.dismissedThisVisit == due.id:
            return []
        default:
            return [violation(.inv1, step, "screen \(step.screen) while \(due.kind) at \(due.date) of \(morning) is due")]
        }
    }

    // MARK: INV4: solved only through C6

    func inv4(_ step: SimStep) -> [InvariantViolation] {
        var found: [InvariantViolation] = []
        for (morning, outcome) in step.after.finished where outcome == .solved && step.before.finished[morning] == nil {
            if let problem = solveProblem(step, morning: morning) {
                found.append(violation(.inv4, step, "\(morning) solved but \(problem)"))
            }
        }
        return found
    }

    private func solveProblem(_ step: SimStep, morning: Date) -> String? {
        guard case .solved(let ringID, _)? = step.event else { return "the event was not solved" }
        guard let open = step.before.challenge, open.ring.id == ringID, open.morning == morning else {
            return "no open challenge for ring \(ringID)"
        }
        guard let due = Oracle.latestDueLatched(in: step.before.target, morning: morning, at: step.now) else {
            return "no latched ring was due"
        }
        if open.level < due.level { return "challenge level \(open.level) < due level \(due.level)" }
        let snapshot = due.challenge ?? .math
        let fellBack = open.kind == .math && unavailable[morning, default: []].contains(snapshot)
        if open.kind != snapshot && !fellBack { return "kind \(open.kind) but the due ring needs \(snapshot)" }
        return nil
    }
}
