import Foundation
import WakelatchCore

/// The app process: launching, coming forward, going away, and alert-button intents (contract P1, B3-B5).
extension MorningSim {
    /// Cold start from `disk` (`launched`, then the reconcile round trip). Ends in `.foreground(.home)`.
    /// Does nothing unless killed.
    public mutating func launch() {
        guard engine == nil else { return }
        if case .locked = process { process = .killed }
        engine = MorningEngine(state: disk, settings: settings, calendar: calendar)
        becomeForeground(.home)
        deliver(.launched(now: now))
        if charging { deliver(.chargingChanged(true, now: now)) }
    }

    /// Opens the app from the icon. Killed: `launch()`. Suspended: `becameActive` on the surface it left.
    /// Locked: unlocks first. Then switches to `surface` when one is given and the cover allows it.
    public mutating func open(to surface: ForegroundSurface? = nil) {
        switch process {
        case .killed:
            launch()
        case .suspended:
            becomeForeground(suspendedSurface)
            deliver(.becameActive(now: now))
        case .locked:
            process = lockedFrom
            open(to: nil)
        case .foreground:
            break
        }
        if let surface { show(surface) }
    }

    /// Sends `enteredBackground` and suspends. Only from the foreground.
    public mutating func suspend() {
        guard case .foreground(let surface) = process else { return }
        suspendedSurface = surface
        process = .suspended
        coverVisible = false
        nextTick = nil
        deliver(.enteredBackground(now: now))
    }

    /// Drops the engine at once (no `enteredBackground`); only `disk` survives.
    public mutating func kill() {
        drop()
    }

    /// Locks the device. From the foreground the app is suspended first.
    public mutating func lock(cancelUnlock: Bool) {
        switch process {
        case .foreground:
            suspend()
            lockedFrom = .suspended
        case .suspended:
            lockedFrom = .suspended
        case .killed:
            lockedFrom = .killed
        case .locked:
            break
        }
        process = .locked(cancelUnlock: cancelUnlock)
    }

    /// Changes what is on screen while foreground (Bedside, a sheet, home). Refused while the morning cover
    /// is up, since home surfaces sit under it. Returns whether the surface changed.
    @discardableResult
    public mutating func show(_ surface: ForegroundSurface) -> Bool {
        guard case .foreground(let current) = process, current != surface, screen == .none else { return false }
        process = .foreground(surface)
        let wasBedside = current == .bedside
        let isBedside = surface == .bedside
        if wasBedside != isBedside { deliver(.bedsideChanged(isBedside, now: now)) }
        return true
    }

    /// Plugs the phone in or out. A running engine hears about it; a launch reports it too.
    public mutating func setCharging(_ on: Bool) {
        charging = on
        deliver(.chargingChanged(on, now: now))
    }

    // MARK: alert buttons

    /// Presses a system alert button. The resulting intent reaches the engine per `intentOrder` and the
    /// process state: killed launches first, suspended comes forward, `locked(cancelUnlock: true)` drops a
    /// foreground intent. Returns the button's action, or nil when the ring was not alerting.
    @discardableResult
    public mutating func press(_ button: AlertButton, on ringID: UUID) -> AlertAction? {
        guard let action = system.press(button, on: ringID) else { return nil }
        switch action {
        case .none:
            if engine != nil, isForeground {
                queue.append(.alertingUpdate)
                drainQueue()
            }
        case .openToChallenge:
            foregroundIntent(.alertAction(ringID: ringID, .openToChallenge, now: now))
        case .confirmAwake:
            backgroundIntent(.alertAction(ringID: ringID, .confirmAwake, now: now))
        }
        return action
    }

    private mutating func foregroundIntent(_ event: Event) {
        if case .locked(let cancelUnlock) = process {
            if cancelUnlock { return }
            process = lockedFrom
        }
        switch process {
        case .killed:
            coldIntent(event)
        case .suspended:
            warmIntent(event)
        case .foreground:
            deliver(event)
        case .locked:
            break
        }
    }

    private mutating func coldIntent(_ event: Event) {
        switch intentOrder {
        case .beforeActive:
            engine = MorningEngine(state: disk, settings: settings, calendar: calendar)
            process = .suspended
            deliver(event)
            guard engine != nil else { return }
            becomeForeground(.home)
            deliver(.launched(now: now))
        case .afterActive:
            launch()
            deliver(event)
        case .afterFirstTick:
            launch()
            deliver(.tick(now: now))
            deliver(event)
        }
    }

    private mutating func warmIntent(_ event: Event) {
        if intentOrder == .beforeActive {
            deliver(event)
            guard engine != nil else { return }
        }
        becomeForeground(suspendedSurface)
        deliver(.becameActive(now: now))
        if intentOrder == .afterFirstTick { deliver(.tick(now: now)) }
        if intentOrder != .beforeActive { deliver(event) }
    }

    /// A background intent never brings the app forward. A killed app is started in the background.
    private mutating func backgroundIntent(_ event: Event) {
        switch process {
        case .killed:
            engine = MorningEngine(state: disk, settings: settings, calendar: calendar)
            process = .suspended
            suspendedSurface = .home
        case .locked where lockedFrom == .killed:
            engine = MorningEngine(state: disk, settings: settings, calendar: calendar)
            lockedFrom = .suspended
            suspendedSurface = .home
        default:
            break
        }
        deliver(event)
    }

    mutating func becomeForeground(_ surface: ForegroundSurface) {
        process = .foreground(surface)
        lastReportedAlerting = system.alerting
        nextTick = now.addingTimeInterval(max(tickInterval, 1))
        coverVisible = false
    }
}
