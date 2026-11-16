import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Found by the real-AlarmKit UI tests: after Home, iOS can keep the app running for a while. A ring that
/// fired then was silenced by the app at once (its SwiftUI cover still "appeared" in the background), and the
/// in-app chime played where nobody could see the screen. Nothing is silenced and no chime plays while the
/// app is not active (F1, F3, F5); the system alarm keeps ringing.
@Suite("F: a running app in the background never takes over")
struct BackgroundTakeoverTests {
    func backgrounded() -> MorningEngine {
        var engine = MorningEngine(state: EngineState(target: Std.morning(nudges: false)),
                                   settings: SimFixture.noNudges.settings, calendar: Std.calendar)
        _ = engine.handle(.launched(now: Std.t(6, 39, 0)))
        _ = engine.handle(.enteredBackground(now: Std.t(6, 39, 5)))
        return engine
    }

    func silenced(_ effects: [Effect]) -> [UUID] {
        effects.compactMap { if case let .silence(id) = $0 { id } else { nil } }
    }

    func plays(_ effects: [Effect]) -> Bool {
        effects.contains { if case .sound(.play) = $0 { true } else { false } }
    }

    @Test("F3, F5: alerting and coverShown in the background neither silence nor play")
    func backgroundAlertingKeepsSystemAlarm() {
        var engine = backgrounded()
        let main = Std.main()
        let alerting = engine.handle(.alerting([main.id], now: Std.t(6, 40, 1), audible: true, coverVisible: true))
        let shown = engine.handle(.coverShown(now: Std.t(6, 40, 2), audible: true))
        #expect(silenced(alerting + shown).isEmpty)
        #expect(!plays(alerting + shown))
    }

    @Test("F3: once the app is active again, the cover takes over as usual")
    func activeAgainTakesOver() {
        var engine = backgrounded()
        let main = Std.main()
        _ = engine.handle(.alerting([main.id], now: Std.t(6, 40, 1), audible: true, coverVisible: true))
        _ = engine.handle(.coverShown(now: Std.t(6, 40, 2), audible: true))
        let active = engine.handle(.becameActive(now: Std.t(6, 40, 5)))
        let alerting = engine.handle(.alerting([main.id], now: Std.t(6, 40, 6), audible: true, coverVisible: false))
        let shown = engine.handle(.coverShown(now: Std.t(6, 40, 7), audible: true))
        // Silencing twice is harmless: the cover presented in the background is visible once active.
        #expect(Set(silenced(active + alerting + shown)) == [main.id])
        #expect(plays(active + alerting + shown))
    }

    @Test("S5: a nudge seen only while in the background, then stopped on the alert, never shows on opening")
    func backgroundNudgeIsNotLatched() {
        var engine = MorningEngine(state: EngineState(target: Std.morning()), settings: SimFixture.standard.settings,
                                   calendar: Std.calendar)
        _ = engine.handle(.launched(now: Std.t(6, 15, 0)))
        _ = engine.handle(.enteredBackground(now: Std.t(6, 15, 5)))
        let nudge = Std.nudge(0)
        _ = engine.handle(.alerting([nudge.id], now: Std.t(6, 20, 1), audible: true, coverVisible: false))
        // Stopped from the system alert; the suspended app misses the update and only reads the table on opening.
        let opened = engine.handle(.becameActive(now: Std.t(6, 20, 8)))
        let rest = Std.morning().filter { $0.id != nudge.id && $0.date > Std.t(6, 20, 8) }
        let table = rest.map { SystemAlarm(id: $0.id, fireDate: $0.date, ring: $0, alerting: false) }
        let read = engine.handle(.systemTable(table, now: Std.t(6, 20, 9)))
        #expect(engine.screen == .none)
        #expect(!plays(opened + read))
    }
}
