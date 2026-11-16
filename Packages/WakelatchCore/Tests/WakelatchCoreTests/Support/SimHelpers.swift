import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

extension MorningSim {
    /// A sim launched the evening before (Sunday 21:00 by default) and then suspended: Monday, Tuesday and
    /// Wednesday mornings are armed.
    static func armed(_ fixture: SimFixture = .standard, at start: Date = Std.t(21, 0, day: 15),
                      order: IntentOrder = .afterActive, audible: Bool = true,
                      disk: EngineState = EngineState()) -> MorningSim {
        var sim = MorningSim(fixture: fixture, start: start, intentOrder: order, audible: audible, disk: disk)
        sim.launch()
        sim.suspend()
        return sim
    }

    /// Advances to `date`, pressing the system Stop on every nudge, main and snooze ring as it starts
    /// alerting (the user snoozing from the lock screen). Deadline and guard rings are left ringing.
    mutating func advanceStoppingSnoozes(to date: Date) {
        while now < date {
            let next = min(date, system.nextFireDate(after: now) ?? date)
            advance(to: next)
            let snoozable = liveSystem().filter { alerting.contains($0.id) && ($0.kind == .nudge || $0.allowsSnooze) }
            for ring in snoozable { press(.stop, on: ring.id) }
        }
    }

    /// Opens the app at the main ring and solves the challenge at `solvedAt`; leaves Released on screen.
    mutating func solveToday(at solvedAt: Date = Std.t(6, 41), morning: Date = Std.today) {
        advanceStoppingSnoozes(to: morning.addingTimeInterval(-10))
        open()
        advance(to: morning.addingTimeInterval(5))
        tapStartChallenge(Std.main(of: morning).id)
        advance(to: solvedAt)
        solveOpenChallenge()
    }

    /// The effects run since `mark` (an earlier `effectLog.count`).
    func effects(since mark: Int) -> [Effect] {
        Array(effectLog[min(mark, effectLog.count)...])
    }

    /// The events delivered since `mark` (an earlier `eventLog.count`).
    func events(since mark: Int) -> [Event] {
        Array(eventLog[min(mark, eventLog.count)...])
    }

    /// Every screen the engine showed since step `mark` (an earlier `steps.count`).
    func screens(since mark: Int) -> [Screen] {
        steps[min(mark, steps.count)...].map(\.screen)
    }

    /// Ids of the rings of `morning` in the fake table.
    func liveIDs(_ kind: RingKind? = nil, morning: Date = Std.today) -> Set<UUID> {
        Set(liveSystem(kind: kind, morning: morning).map(\.id))
    }
}

func ids(_ rings: [Ring]) -> Set<UUID> { Set(rings.map(\.id)) }

func silenced(_ effects: [Effect]) -> Set<UUID> {
    Set(effects.compactMap { effect -> UUID? in
        if case .silence(let id) = effect { return id }
        return nil
    })
}

func cancelled(_ effects: [Effect]) -> Set<UUID> {
    Set(effects.compactMap { effect -> UUID? in
        if case .cancel(let id) = effect { return id }
        return nil
    })
}

func scheduled(_ effects: [Effect]) -> [Ring] {
    effects.compactMap { effect -> Ring? in
        if case .schedule(let ring) = effect { return ring }
        return nil
    }
}

func playsChime(_ effects: [Effect]) -> Bool {
    effects.contains { effect in
        if case .sound(.play) = effect { return true }
        return false
    }
}

func isAlertAction(_ event: Event) -> Bool {
    if case .alertAction = event { return true }
    return false
}

/// Every invariant held at every step of the sim.
func expectClean(_ sim: MorningSim, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(sim.checker.violationCount == 0,
            "\(sim.checker.violationCount) invariant violations, first: \(sim.violations.prefix(3))",
            sourceLocation: sourceLocation)
}
