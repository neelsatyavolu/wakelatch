import Foundation

/// One scheduled ring, as much as is needed to tell whether its morning has started.
public struct MorningRing: Equatable, Sendable {
    public let morning: Date
    public let date: Date
    public let latched: Bool

    public init(morning: Date, date: Date, latched: Bool) {
        self.morning = morning
        self.date = date
        self.latched = latched
    }
}

/// A morning is under way from its first ring (a nudge counts) until ten minutes after its last
/// latched ring. Rescheduling must keep such a morning's rings: dropping them once the first nudge
/// has rung silenced the rest of the morning.
public enum MorningUnderWay {
    public static let grace: TimeInterval = 10 * 60

    public static func find(in rings: [MorningRing], now: Date) -> Date? {
        let started = Set(rings.filter { $0.date <= now }.map(\.morning))
        for morning in started.sorted(by: >) {
            let own = rings.filter { $0.morning == morning }
            let end = own.filter(\.latched).map(\.date).max() ?? own.map(\.date).max() ?? morning
            if now <= end.addingTimeInterval(grace) { return morning }
        }
        return nil
    }
}
