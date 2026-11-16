import Foundation

/// Keeps the total number of scheduled alarms under AlarmKit's budget (D2).
public enum ScheduleBudget {
    public static let limit = 250

    /// `mornings` are the future rings of each armed morning, nearest first; `reserved` counts alarms that
    /// must stay (the active morning's remaining rings and pending awake checks).
    /// Removes guard rings from the farthest morning first, latest guard first. The first morning in
    /// `mornings` is never trimmed. If every later morning has lost all its guards and the total is still
    /// over `limit`, whole mornings are dropped, farthest first. Returns the kept rings in the same order;
    /// a dropped morning is left out of the result.
    public static func trim(_ mornings: [[Ring]], reserved: Int, limit: Int = limit) -> [[Ring]] {
        var kept = mornings
        var total = reserved + mornings.reduce(0) { $0 + $1.count }
        guard total > limit, kept.count > 1 else { return mornings }
        for index in stride(from: kept.count - 1, through: 1, by: -1) {
            while total > limit, let last = kept[index].lastIndex(where: { $0.kind == .guardRing }) {
                kept[index].remove(at: last)
                total -= 1
            }
        }
        var dropped = Set<Int>()
        for index in stride(from: kept.count - 1, through: 1, by: -1) where total > limit {
            total -= kept[index].count
            dropped.insert(index)
        }
        return kept.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }
}
