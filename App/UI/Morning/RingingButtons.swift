import WakelatchCore

/// The buttons the ringing screen offers, worked out from the engine's screen alone (contract S4, C8).
enum RingingButton: Equatable, CaseIterable {
    /// A nudge: one tap and it stops.
    case stopNudge
    /// Main or snooze ring: open the challenge.
    case startChallenge
    /// Main or snooze ring that is sounding now. A snoozed screen (D1) does not offer it again.
    case snooze
    /// Deadline or guard ring: only the challenge stops it.
    case solve

    static func buttons(for ring: Ring, sounding: Bool) -> [RingingButton] {
        if ring.kind == .nudge { return [.stopNudge] }
        guard ring.allowsSnooze else { return [.solve] }
        return sounding ? [.startChallenge, .snooze] : [.startChallenge]
    }
}
