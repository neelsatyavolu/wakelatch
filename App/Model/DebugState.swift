import Foundation
import WakelatchCore

/// The value of the hidden `debug.state` element that UI tests decode.
struct DebugState: Codable, Equatable {
    /// none, ringing, challenge, awakeCheck or released.
    let screen: String
    /// The ring on screen (for a challenge, its ring).
    let ring: UUID?
    let kind: String?
    let level: Int?
    let sounding: Bool?
    /// The challenge kind the screen asks for.
    let challenge: String?
    /// Ideal of the ring's morning, seconds since 1970.
    let morning: Double?
    /// Ideal of the earliest morning in target, seconds since 1970: the app's own time for a pinned morning.
    let firstMorning: Double?
    let acknowledged: Int
    /// Alarms in AlarmKit's table at the last read or update.
    let scheduled: Int
    /// The same alarms by ring kind ("unknown" for alarms without a ring).
    let byKind: [String: Int]
    /// Of those, the alarms alerting now. Zero under the morning cover once the app has taken over (F3, F4).
    let alerting: Int
    /// Alert-button intents this install has received. A UI test reads it to tell an intent the system never
    /// delivered (the simulator) from an app bug.
    let intents: Int
    let skipsLeft: Int
    /// The in-app sound the app is playing ("chime" or "nudge"), nil when quiet. Under UI tests nothing is
    /// heard; this says what would be.
    let sound: PlayingSound?

    init(screen: Screen, state: EngineState, table: [SystemAlarm]?, intents: Int = 0, skipsLeft: Int = 0,
         sound: PlayingSound? = nil) {
        let shown = Self.describe(screen)
        self.screen = shown.name
        ring = shown.ring?.id
        kind = shown.ring?.kind.rawValue
        level = shown.ring?.level
        sounding = shown.sounding
        challenge = shown.challenge?.rawValue
        morning = shown.ring?.morning.timeIntervalSince1970
        firstMorning = state.target.filter(\.latched).map(\.morning).min()?.timeIntervalSince1970
        acknowledged = state.acknowledged.count
        scheduled = table?.count ?? 0
        byKind = (table ?? []).reduce(into: [:]) { counts, alarm in
            counts[alarm.ring?.kind.rawValue ?? "unknown", default: 0] += 1
        }
        alerting = (table ?? []).filter(\.alerting).count
        self.intents = intents
        self.skipsLeft = skipsLeft
        self.sound = sound
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func describe(_ screen: Screen)
        -> (name: String, ring: Ring?, sounding: Bool?, challenge: ChallengeKind?) {
        switch screen {
        case .none: ("none", nil, nil, nil)
        case let .ringing(ring, sounding, _): ("ringing", ring, sounding, ring.challenge)
        case let .challenge(open): ("challenge", open.ring, nil, open.kind)
        case let .awakeCheck(ring): ("awakeCheck", ring, nil, nil)
        case .released: ("released", nil, nil, nil)
        }
    }
}
