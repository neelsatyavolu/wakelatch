import Foundation

/// A latched alarm: the first ring plus guard rings that follow at a fixed
/// interval. Every ring is handed to the system ahead of time, so if the user
/// taps Stop or leaves the app without finishing the challenge, the next ring
/// still happens. Finishing the challenge cancels whatever is left.
public struct GuardChain: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case intervalTooShort
        case negativeGuardCount
    }

    public static let minimumInterval: TimeInterval = 30

    public let firstFire: Date
    public let interval: TimeInterval
    public let guardCount: Int

    public init(firstFire: Date, interval: TimeInterval, guardCount: Int) throws {
        guard interval >= Self.minimumInterval else { throw Error.intervalTooShort }
        guard guardCount >= 0 else { throw Error.negativeGuardCount }
        self.firstFire = firstFire
        self.interval = interval
        self.guardCount = guardCount
    }

    /// The first ring followed by each guard ring, in order.
    public var fireDates: [Date] {
        (0...guardCount).map { firstFire.addingTimeInterval(Double($0) * interval) }
    }

    public var lastFire: Date {
        firstFire.addingTimeInterval(Double(guardCount) * interval)
    }

    /// Rings strictly later than `date`.
    public func fireDates(after date: Date) -> [Date] {
        fireDates.filter { $0 > date }
    }

    /// Index of the latest ring at or before `date`: the one the user owes a
    /// challenge for. Nil before the first ring or for an empty chain.
    public static func dueRing(in fireDates: [Date], at date: Date) -> Int? {
        fireDates.lastIndex { $0 <= date }
    }
}
