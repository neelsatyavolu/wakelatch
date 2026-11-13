import Foundation
import Observation
import WakelatchCore

/// Spike state kept in UserDefaults so it survives force-quit and reboot.
/// The stop intent runs in the app's own process, so no app group is needed.
@MainActor
@Observable
final class LatchStore {
    static let shared = LatchStore()

    private enum Key {
        static let chainIDs = "chainIDs"
        static let chainDates = "chainDates"
        static let pendingRing = "pendingRing"
        static let challengePending = "challengePending"
        static let log = "eventLog"
    }

    private static let maxLogLines = 400
    private let defaults = UserDefaults.standard

    private(set) var chainIDs: [UUID]
    private(set) var chainDates: [Date]
    /// Index in the chain of the ring whose Stop or Solve opened the app.
    private(set) var pendingRing: Int?
    private(set) var challengePending: Bool
    private(set) var log: [String]

    private init() {
        chainIDs = (defaults.stringArray(forKey: Key.chainIDs) ?? []).compactMap(UUID.init(uuidString:))
        chainDates = (defaults.array(forKey: Key.chainDates) as? [Date]) ?? []
        challengePending = defaults.bool(forKey: Key.challengePending)
        pendingRing = defaults.object(forKey: Key.pendingRing) as? Int
        log = defaults.stringArray(forKey: Key.log) ?? []
    }

    func setChain(_ ids: [UUID], dates: [Date]) {
        chainIDs = ids
        chainDates = dates
        defaults.set(ids.map(\.uuidString), forKey: Key.chainIDs)
        defaults.set(dates, forKey: Key.chainDates)
    }

    func setChallengePending(_ pending: Bool, ring: Int? = nil) {
        challengePending = pending
        pendingRing = pending ? ring : nil
        defaults.set(pending, forKey: Key.challengePending)
        defaults.set(pendingRing, forKey: Key.pendingRing)
    }

    /// Re-read values another code path (an intent) may have written.
    func reload() {
        challengePending = defaults.bool(forKey: Key.challengePending)
        pendingRing = defaults.object(forKey: Key.pendingRing) as? Int
        log = defaults.stringArray(forKey: Key.log) ?? []
    }

    /// Opens the challenge when an armed chain has a ring that is due. This
    /// does not rely on the alarm's intent: however the app comes forward
    /// (Stop, Solve, or the user opening it), a due ring means a challenge.
    func latchIfDue(now: Date = .now, reason: String) {
        guard !chainIDs.isEmpty, !challengePending,
              let ring = GuardChain.dueRing(in: chainDates, at: now) else { return }
        setChallengePending(true, ring: ring)
        record("ring \(ring + 1) due (\(reason)); challenge shown")
    }

    func record(_ message: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        let updated = Array(([stamp + "  " + message] + log).prefix(Self.maxLogLines))
        log = updated
        defaults.set(updated, forKey: Key.log)
    }

    func resetAll() {
        for key in [Key.chainIDs, Key.chainDates, Key.pendingRing, Key.challengePending, Key.log] {
            defaults.removeObject(forKey: key)
        }
        chainIDs = []
        chainDates = []
        pendingRing = nil
        challengePending = false
        log = []
    }

    func clearLog() {
        log = []
        defaults.removeObject(forKey: Key.log)
    }
}
