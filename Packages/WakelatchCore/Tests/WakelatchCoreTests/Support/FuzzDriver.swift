import Foundation
import WakelatchCore
import WakelatchCoreTestSupport

/// Seeded random user, clock and process behaviour for the property tests. The same seed always gives the
/// same run, so a failing seed can be replayed and turned into a named regression test.
struct FuzzDriver {
    var rng: SeededGenerator
    /// A second stream for the long-window, short-snooze and late-call choices added in review, so the
    /// draws of `rng` (and the histories of named seeds) stay as they were.
    var wide: SeededGenerator
    /// One line per action, for failure messages.
    var trace: [String] = []
    private var staleTable: [SystemAlarm] = []

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
        wide = SeededGenerator(seed: seed ^ 0x5EED_0F_B0D6E7)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < probability }
    mutating func wideInt(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &wide) }
    mutating func wideChance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &wide) < probability }

    /// Ideal 05:00, Deadline 08:00, 3-minute snoozes: three mornings go over the D2 budget, so the trim runs.
    static let threeHours = SimFixture.standard {
        $0.times = WakeTimes(ideal: ClockTime(hour: 5, minute: 0), deadline: ClockTime(hour: 8, minute: 0))
        $0.timing = .production(PlanOptions(snoozeMinutes: 3))
    }

    /// A launched sim starting somewhere between the evening before and the end of Monday's morning.
    /// A quarter start with three-hour mornings; half let an AlarmKit call sent before a kill land late.
    mutating func makeSim() -> MorningSim {
        let starts = [Std.t(21, 0, day: 15), Std.t(6, 0), Std.t(6, 25), Std.t(6, 39), Std.t(6, 50), Std.t(7, 15)]
        let start = starts[int(0...starts.count - 1)].addingTimeInterval(Double(int(0...300)))
        let fixture = wideChance(0.25) ? Self.threeHours : .standard
        let faults = SimFaults(scheduleLatency: chance(0.3) ? int(1...2) : 0,
                               inFlightSurvivesKill: wideChance(0.5))
        var sim = MorningSim(fixture: fixture, start: start, faults: faults,
                             intentOrder: IntentOrder.allCases[int(0...2)], audible: chance(0.5))
        sim.tickInterval = 30
        sim.launch()
        trace.append("start \(start) latency \(sim.faults.scheduleLatency) order \(sim.intentOrder) audible \(sim.audible) "
            + "window \(fixture.settings.times.windowMinutes) late calls \(faults.inFlightSurvivesKill)")
        return sim
    }

    /// One random action. In-app taps only happen on a visible cover and settings only change in the
    /// foreground, as in the app; anything else falls back to letting time pass.
    mutating func step(_ sim: inout MorningSim) {
        let roll = int(0...99)
        let onCover = sim.isForeground && sim.coverVisible
        if !onCover, (62..<84).contains(roll) {
            return advance(&sim, seconds: int(5...60))
        }
        if !sim.isForeground, (86..<90).contains(roll) {
            return advance(&sim, seconds: int(5...60))
        }
        switch roll {
        case 0..<22: advance(&sim, seconds: int(5...90))
        case 22..<32: advance(&sim, seconds: int(120...900))
        case 32..<38: openApp(&sim)
        case 38..<42: note("suspend"); sim.suspend()
        case 42..<44: note("kill"); sim.kill()
        case 44..<47: lockDevice(&sim)
        case 47..<50: showSurface(&sim)
        case 50..<62: pressAlert(&sim)
        case 62..<76: tapScreen(&sim)
        case 76..<80: rawTap(&sim)
        case 80..<82: skip(&sim)
        case 82..<84: unavailable(&sim)
        case 84..<86: note("charging \(!sim.charging)"); sim.setCharging(!sim.charging)
        case 86..<90: changeSettings(&sim)
        case 90..<91: changeZone(&sim)
        case 91..<93: crash(&sim)
        case 93..<95: rawAlertAction(&sim)
        case 95..<97: note("settle"); sim.settle()
        default: staleRead(&sim)
        }
    }

    private mutating func note(_ line: String) {
        trace.append(line)
    }

    private mutating func randomRing(_ sim: MorningSim) -> Ring? {
        let target = sim.state.target
        return target.isEmpty ? nil : target[int(0...target.count - 1)]
    }

    private mutating func surface() -> ForegroundSurface {
        [ForegroundSurface.home, .bedside, .sheet(.settings), .sheet(.time)][int(0...3)]
    }

    private mutating func advance(_ sim: inout MorningSim, seconds: Int) {
        note("advance \(seconds)s")
        if chance(0.1) { staleTable = sim.system.snapshot }
        sim.advance(by: TimeInterval(seconds))
    }

    private mutating func openApp(_ sim: inout MorningSim) {
        let to: ForegroundSurface? = chance(0.5) ? surface() : nil
        note("open \(String(describing: to))")
        sim.open(to: to)
    }

    private mutating func lockDevice(_ sim: inout MorningSim) {
        let cancel = chance(0.5)
        note("lock cancelUnlock \(cancel)")
        sim.lock(cancelUnlock: cancel)
    }

    private mutating func showSurface(_ sim: inout MorningSim) {
        let to = surface()
        note("show \(to)")
        sim.show(to)
    }

    private mutating func pressAlert(_ sim: inout MorningSim) {
        let alerting = sim.alerting.sorted { $0.uuidString < $1.uuidString }
        guard !alerting.isEmpty else { return advance(&sim, seconds: int(5...60)) }
        let id = alerting[int(0...alerting.count - 1)]
        let button: AlertButton = chance(0.5) ? .stop : .secondary
        note("press \(button) on \(sim.system.table[id]?.ring.kind.rawValue ?? "?")")
        sim.press(button, on: id)
    }

    private mutating func tapScreen(_ sim: inout MorningSim) {
        switch sim.screen {
        case .ringing(let ring, _, _):
            switch int(0...2) {
            case 0: note("tapSnooze \(ring.kind)"); sim.tapSnooze(ring.id)
            case 1: note("tapStartChallenge \(ring.kind)"); sim.tapStartChallenge(ring.id)
            default: note("tapNudgeStop \(ring.kind)"); sim.tapNudgeStop(ring.id)
            }
        case .challenge(let open):
            let id = chance(0.8) ? open.ring.id : (randomRing(sim)?.id ?? open.ring.id)
            note("solved \(id == open.ring.id ? "open ring" : "other ring")")
            sim.solve(id)
        case .awakeCheck(let ring):
            note("tapImUp"); sim.tapImUp(ring.id)
        case .released:
            note("closeReleased"); sim.closeReleased()
        case .none:
            if let ring = randomRing(sim) { note("tapStartChallenge random \(ring.kind)"); sim.tapStartChallenge(ring.id) }
        }
    }

    private mutating func rawTap(_ sim: inout MorningSim) {
        guard let ring = randomRing(sim) else { return }
        note("raw tap \(ring.kind)")
        switch int(0...4) {
        case 0: sim.tapSnooze(ring.id)
        case 1: sim.tapStartChallenge(ring.id)
        case 2: sim.tapNudgeStop(ring.id)
        case 3: sim.solve(ring.id)
        default: sim.tapImUp(ring.id)
        }
    }

    private mutating func skip(_ sim: inout MorningSim) {
        guard let id = sim.openChallenge?.ring.id ?? randomRing(sim)?.id else { return }
        note("skip")
        sim.skip(id)
    }

    private mutating func unavailable(_ sim: inout MorningSim) {
        let kind = ChallengeKind.allCases[int(0...ChallengeKind.allCases.count - 1)]
        note("challengeUnavailable \(kind)")
        sim.challengeUnavailable(kind)
    }

    private mutating func changeSettings(_ sim: inout MorningSim) {
        let choice = int(0...6)
        let kinds = ChallengeKind.allCases
        let idealMinutes = 300 + 5 * int(0...36)
        let short = 5 * int(0...12)
        let window = wideChance(0.4) ? 5 * wideInt(13...36) : short
        let snooze = [3, 5, 9][wideInt(0...2)]
        let kind = kinds[int(0...kinds.count - 1)]
        note("settings change \(choice)")
        sim.changeSettings { settings in
            switch choice {
            case 0: settings.awakeChecks.toggle()
            case 1: settings.enabled.toggle()
            case 2:
                let deadline = idealMinutes + window
                settings.times = WakeTimes(ideal: ClockTime(hour: idealMinutes / 60, minute: idealMinutes % 60),
                                           deadline: ClockTime(hour: deadline / 60, minute: deadline % 60))
            case 3: settings.snoozeChallenge = kind
            case 4: settings.deadlineChallenge = kind
            case 5:
                settings.timing = .production(PlanOptions(nudges: settings.timing.nudgeOffsets.isEmpty,
                                                          snoozeMinutes: snooze))
            default: settings.keepScreenOn.toggle()
            }
        }
    }

    private mutating func changeZone(_ sim: inout MorningSim) {
        let next = sim.calendar.timeZone.identifier == "America/New_York" ? Std.calendar : Std.newYork
        note("calendar \(next.timeZone.identifier)")
        sim.changeCalendar(next)
    }

    private mutating func crash(_ sim: inout MorningSim) {
        let after = int(0...15)
        note("killAfter \(after)")
        sim.killAfter(effects: after)
        if chance(0.5) { sim.open() } else { changeSettings(&sim) }
        sim.faults.killAfterEffect = nil
    }

    private mutating func rawAlertAction(_ sim: inout MorningSim) {
        guard let ring = randomRing(sim) else { return }
        let action: AlertAction = ring.kind == .awakeCheck ? .confirmAwake : .openToChallenge
        note("raw alertAction \(action) \(ring.kind)")
        sim.send(.alertAction(ringID: ring.id, action, now: sim.now))
    }

    private mutating func staleRead(_ sim: inout MorningSim) {
        guard !staleTable.isEmpty else { return }
        note("stale systemTable")
        sim.send(.systemTable(staleTable, now: sim.now))
    }
}
