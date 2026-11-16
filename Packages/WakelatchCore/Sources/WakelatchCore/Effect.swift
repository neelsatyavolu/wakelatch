import Foundation

/// Work the app runs after `MorningEngine.handle`, in the order given.
public enum Effect: Hashable, Sendable {
    /// Save `engine.state`. Always first when the state changed, before any AlarmKit call.
    case persist
    /// Hand this ring to AlarmKit with `AlertSpec.for(ring.kind)`; reply with `.scheduled`.
    case schedule(Ring)
    /// Stop and remove this alarm from AlarmKit.
    case cancel(UUID)
    /// Stop an alerting system alarm without removing later rings (the in-app screen took over).
    case silence(UUID)
    case sound(SoundCommand)
    /// Close Settings, the time picker and any other sheet so the morning cover can present.
    case dismissHomeSheets
    case setIdleTimerDisabled(Bool)
    /// Read AlarmKit's table and send `.systemTable`.
    case readSystemTable
    /// A one-off morning finished: turn the alarm off in the user's settings, save them, and send them back
    /// with `settingsChanged`. Settings with `enabled == false` tell the engine the turn-off was saved; until
    /// then it treats settings saying enabled as stale and sends this again (A4).
    case disableAlarm
}
