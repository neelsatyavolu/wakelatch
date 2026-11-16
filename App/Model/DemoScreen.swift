import Foundation
import WakelatchCore

/// Screenshot mode (`-uitest-show=<name>`): a sample morning screen with rings that are never scheduled.
struct DemoScreen {
    let screen: Screen
    let rings: [Ring]
    /// The time the morning screens show.
    let now: Date
    let bedside: Bool

    static func make(_ name: String, settings: UserSettings, now: Date, calendar: Calendar) -> DemoScreen? {
        let engine = settings.engineSettings(test: nil)
        guard let rings = try? MorningPlan.build(on: now, times: engine.times, timing: engine.timing,
                                                 challenges: engine.challenges, calendar: calendar),
              let morning = rings.first(where: \.latched)?.morning else { return nil }
        let latched = rings.filter(\.latched)
        let ring = latched.first { $0.kind == .snooze && $0.date.timeIntervalSince(morning) >= 18 * 60 } ?? latched[0]
        let deadline = latched.first { $0.kind == .deadline } ?? ring
        let screen: Screen
        switch name {
        case "ringing": screen = .ringing(ring, sounding: true, snoozedUntil: nil)
        case "snoozed":
            let next = latched.first { $0.date > ring.date }
            screen = .ringing(ring, sounding: false, snoozedUntil: next?.date)
        case "challenge": screen = .challenge(ActiveChallenge(ring: ring, kind: ring.challenge ?? .math))
        case "released":
            screen = .released(MorningRecord(morning: morning, deadline: deadline.date, outcome: .solved,
                                             upAt: morning.addingTimeInterval(12 * 60)))
        default: screen = .none
        }
        return DemoScreen(screen: screen, rings: rings, now: ring.date, bedside: name == "night")
    }
}
