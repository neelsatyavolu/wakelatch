import Foundation
import WakelatchCore

/// Delivering events, running effects, and checking invariants.
extension MorningSim {
    /// Sends one event and everything it causes (system table reads, schedule replies, alerting changes,
    /// cover presentation). Returns the effects of `event` itself.
    @discardableResult
    mutating func deliver(_ event: Event) -> [Effect] {
        guard engine != nil else { return [] }
        queue.append(.event(event, fresh: false))
        return drainQueue() ?? []
    }

    /// Processes the queue until it is empty; returns the effects of the first event delivered.
    @discardableResult
    mutating func drainQueue() -> [Effect]? {
        drain = DrainState()
        var first: [Effect]?
        while !queue.isEmpty {
            let item = queue.removeFirst()
            guard engine != nil else {
                queue.removeAll()
                break
            }
            guard let resolved = resolve(item) else { continue }
            let effects = step(resolved.event, fresh: resolved.fresh)
            if first == nil { first = effects }
        }
        finishDrain()
        return first
    }

    private mutating func resolve(_ item: QueueItem) -> (event: Event, fresh: Bool)? {
        switch item {
        case .event(let event, let fresh):
            return (event, fresh)
        case .alertingUpdate:
            guard isForeground, system.alerting != lastReportedAlerting else { return nil }
            lastReportedAlerting = system.alerting
            return (.alerting(system.alerting, now: now, audible: audible, coverVisible: coverVisible), false)
        }
    }

    private mutating func step(_ event: Event, fresh: Bool) -> [Effect] {
        guard var running = engine else { return [] }
        let before = running.state
        let screenBefore = running.screen
        let processBefore = process
        let coverBefore = coverVisible
        let systemBefore = system
        let effects = running.handle(event)
        engine = running
        drain.delivered = true
        eventLog.append(event)
        if case .systemTable(let alarms, _) = event {
            lastReportedAlerting = Set(alarms.filter(\.alerting).map(\.id))
        }

        var ran: [Effect] = []
        for effect in effects {
            run(effect)
            ran.append(effect)
            if killIfFaulted() { break }
        }
        let killed = engine == nil
        if !killed { advanceDriver() }

        let after = running.state
        if fresh, case .systemTable = event {
            drain.freshRead = true
            drain.targetChangedSinceRead = false
        } else if before.target != after.target {
            drain.targetChangedSinceRead = true
        }
        steps.append(SimRecord(now: now, event: event, effects: ran, screen: running.screen,
                               stateChanged: before != after, targetChanged: before.target != after.target,
                               truncated: killed))
        observe(SimStep(now: now, event: event, effects: ran, processBefore: processBefore, process: process,
                        before: before, after: after, screenBefore: screenBefore, screen: running.screen,
                        session: running.session, systemBefore: systemBefore, system: system,
                        coverVisible: coverBefore, inFlight: inFlight, quiescent: false, reconcileSettled: false,
                        sound: sound, idleTimerDisabled: idleTimerDisabled))
        if !killed {
            updateCover()
            queue.append(.alertingUpdate)
        }
        return ran
    }

    private mutating func finishDrain() {
        guard let running = engine, !drain.killed else { return }
        let settled = drain.freshRead && !drain.targetChangedSinceRead && driver.isEmpty
        observe(SimStep(now: now, event: nil, effects: [], processBefore: process, process: process,
                        before: running.state, after: running.state, screenBefore: running.screen,
                        screen: running.screen, session: running.session, systemBefore: system, system: system,
                        coverVisible: coverVisible, inFlight: inFlight, quiescent: true, reconcileSettled: settled,
                        sound: sound, idleTimerDisabled: idleTimerDisabled, outputsCurrent: drain.delivered))
    }

    private mutating func observe(_ step: SimStep) {
        checker.observe(step, settings: settings, calendar: calendar)
    }

    // MARK: effects

    private mutating func run(_ effect: Effect) {
        effectLog.append(effect)
        switch effect {
        case .persist:
            if let running = engine { disk = running.state }
        case .schedule(let ring):
            enqueueDriver(.schedule(ring), latency: faults.scheduleLatency)
        case .cancel(let id):
            enqueueDriver(.cancel(id), latency: faults.cancelLatency)
        case .silence(let id):
            system.stop(id)
        case .sound(let command):
            sound = command == .stop ? .silent : soundPlaying(command)
        case .dismissHomeSheets:
            // The app's UI state lives on while suspended, so a sheet left open is closed then too.
            if case .foreground(.sheet) = process { process = .foreground(.home) }
            if case .sheet = suspendedSurface { suspendedSurface = .home }
        case .setIdleTimerDisabled(let disabled):
            idleTimerDisabled = disabled
        case .readSystemTable:
            enqueueDriver(.read, latency: 0)
        case .disableAlarm:
            // The app saves the turn-off and passes its settings on, which tells the engine it was saved (A4).
            settings.enabled = false
            queue.append(.event(.settingsChanged(settings, now: now), fresh: false))
        }
    }

    private func soundPlaying(_ command: SoundCommand) -> SimSound {
        if case .play(let nudge) = command { return .playing(nudge: nudge) }
        return .silent
    }

    /// Schedules wait `latency` steps; anything issued while calls are in flight (a cancel, a table read) waits
    /// behind them, as on the app's serial AlarmKit driver.
    private mutating func enqueueDriver(_ kind: DriverOp.Kind, latency: Int) {
        let behind = driver.last?.remaining ?? 0
        let remaining = max(latency, behind)
        if remaining <= 0 {
            land(kind)
        } else {
            driver.append(DriverOp(kind: kind, remaining: remaining))
        }
    }

    /// One step passed: in-flight calls count down and land in order.
    private mutating func advanceDriver() {
        for index in driver.indices { driver[index].remaining -= 1 }
        while let op = driver.first, op.remaining <= 0 {
            driver.removeFirst()
            land(op.kind)
        }
    }

    mutating func land(_ kind: DriverOp.Kind) {
        switch kind {
        case .schedule(let ring):
            let ok = (try? system.schedule(ring, fails: faults.scheduleFails)) != nil
            queue.append(.event(.scheduled(ring.id, ok: ok, now: now), fresh: false))
        case .cancel(let id):
            system.cancel(id)
        case .read:
            let table = system.snapshot
            let stale = orphaned != nil
            landOrphan()
            queue.append(.event(.systemTable(table, now: now), fresh: !stale))
        }
    }

    /// A call a killed process had already sent lands now, after the table was read; its reply is lost.
    private mutating func landOrphan() {
        guard let kind = orphaned else { return }
        orphaned = nil
        switch kind {
        case .schedule(let ring): try? system.schedule(ring, fails: faults.scheduleFails)
        case .cancel(let id): system.cancel(id)
        case .read: break
        }
    }

    /// Lands every in-flight call and drains until nothing is in flight.
    public mutating func settle() {
        while engine != nil, !driver.isEmpty {
            let ops = driver
            driver = []
            for op in ops { land(op.kind) }
            drainQueue()
        }
    }

    // MARK: faults and cover

    /// Kills the process right after the `n`th effect (0-based) run from now on.
    public mutating func killAfter(effects n: Int) {
        faults.killAfterEffect = n
        faultCounter = 0
    }

    private mutating func killIfFaulted() -> Bool {
        guard let limit = faults.killAfterEffect else { return false }
        faultCounter += 1
        guard faultCounter > limit else { return false }
        faults.killAfterEffect = nil
        faultCounter = 0
        drop()
        return true
    }

    /// The process dies: engine, queue and queued calls are gone; the disk stays. The call already sent may
    /// survive (`faults.inFlightSurvivesKill`).
    mutating func drop() {
        landOrphan()
        if faults.inFlightSurvivesKill, let head = driver.first { orphaned = head.kind }
        engine = nil
        process = .killed
        driver = []
        queue = []
        coverVisible = false
        sound = .silent
        idleTimerDisabled = false
        nextTick = nil
        drain.killed = true
        suspendedSurface = .home
    }

    /// Presents the cover once the screen shows something and no sheet is in the way.
    private mutating func updateCover() {
        guard let running = engine, case .foreground(let surface) = process, running.screen != .none else {
            coverVisible = false
            return
        }
        if case .sheet = surface { return }
        guard !coverVisible else { return }
        coverVisible = true
        queue.append(.event(.coverShown(now: now, audible: audible), fresh: false))
    }
}
