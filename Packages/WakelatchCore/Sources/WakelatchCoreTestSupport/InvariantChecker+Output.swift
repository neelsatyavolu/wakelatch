import Foundation
import WakelatchCore

extension InvariantChecker {
    // MARK: INV13: the chime and the idle timer follow the screen (F1, F7)

    /// At each quiescent foreground step where the engine handled an event at that time, the app's chime is
    /// playing exactly for a sounding ringing screen, and the idle timer is disabled exactly as rule F7 says.
    func inv13(_ step: SimStep, settings: EngineSettings) -> [InvariantViolation] {
        guard step.isForeground, step.outputsCurrent else { return [] }
        var found: [InvariantViolation] = []
        let sound: SimSound
        if case .ringing(let ring, sounding: true, _) = step.screen {
            sound = .playing(nudge: ring.kind == .nudge)
        } else {
            sound = .silent
        }
        if step.sound != sound {
            found.append(violation(.inv13, step, "sound \(step.sound) but screen \(step.screen) needs \(sound)"))
        }
        let idle = idleTimerDisabled(step, settings: settings)
        if step.idleTimerDisabled != idle {
            found.append(violation(.inv13, step, "idle timer disabled \(step.idleTimerDisabled), F7 says \(idle)"))
        }
        return found
    }

    /// F7: ringing, challenge or awake check; Released within `releasedKeepAwake` of the solve; or Bedside
    /// with keep-screen-on while charging.
    private func idleTimerDisabled(_ step: SimStep, settings: EngineSettings) -> Bool {
        let session = step.session
        let bedside = session.bedside && settings.keepScreenOn && session.charging
        switch step.screen {
        case .ringing, .challenge, .awakeCheck:
            return true
        case .released:
            let fresh = session.released.map {
                step.now.timeIntervalSince($0.since) < settings.timing.releasedKeepAwake
            } ?? false
            return fresh || bedside
        case .none:
            return bedside
        }
    }
}
