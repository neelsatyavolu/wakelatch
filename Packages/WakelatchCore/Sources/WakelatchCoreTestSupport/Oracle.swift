import Foundation
import WakelatchCore

/// The contract's definitions (docs/morning-contract.md, Terms and rule L1), computed from `EngineState`
/// alone. The invariant checker and the tests use these instead of the engine's own queries, so a wrong
/// query cannot hide a wrong decision.
public enum Oracle {
    /// Every ring of `morning` in `target`, oldest first.
    public static func rings(of morning: Date, in target: [Ring]) -> [Ring] {
        target.filter { $0.morning == morning }.sorted { $0.date < $1.date }
    }

    /// L1: the oldest morning whose first ring in target (a nudge counts, awake checks do not) or Ideal is due,
    /// that is not finished, and whose last latched ring plus grace is not yet past.
    public static func activeMorning(in state: EngineState, at now: Date, grace: TimeInterval) -> Date? {
        var first: [Date: Date] = [:]
        var lastLatched: [Date: Date] = [:]
        for ring in state.target where ring.kind != .awakeCheck {
            first[ring.morning] = min(first[ring.morning] ?? ring.date, ring.date)
            if ring.latched {
                lastLatched[ring.morning] = max(lastLatched[ring.morning] ?? ring.date, ring.date)
            }
        }
        for morning in first.keys.sorted() where state.finished[morning] == nil {
            guard let start = first[morning], min(start, morning) <= now,
                  let last = lastLatched[morning], now <= last.addingTimeInterval(grace) else { continue }
            return morning
        }
        return nil
    }

    /// The due latched ring of `morning` with the highest level, then the greatest date, at or before `now`
    /// (the bar a morning must clear only goes up).
    public static func latestDueLatched(in target: [Ring], morning: Date, at now: Date) -> Ring? {
        target.filter { $0.morning == morning && $0.latched && $0.date <= now }
            .max { ($0.level, $0.date) < ($1.level, $1.date) }
    }

    /// The first latched ring of `morning` after `now`.
    public static func nextLatched(in target: [Ring], morning: Date, after now: Date) -> Ring? {
        target.filter { $0.morning == morning && $0.latched && $0.date > now }.min { $0.date < $1.date }
    }

    /// The last latched ring of `morning` plus grace: when it ends as missed.
    public static func endsBy(of morning: Date, in target: [Ring], grace: TimeInterval) -> Date? {
        target.filter { $0.morning == morning && $0.latched }.map(\.date).max()?.addingTimeInterval(grace)
    }
}
