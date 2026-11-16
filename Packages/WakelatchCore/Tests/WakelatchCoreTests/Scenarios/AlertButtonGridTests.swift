import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group R, generated: every ring kind x system button x process state x intent order (contract B2-B5, P1).
/// The process state never changes the outcome, except a locked device whose user cancels the unlock.
@Suite("R: alert buttons, every kind x button x process x intent order")
struct AlertButtonGridTests {
    @Test("R grid: the button's outcome is the same in every process state", arguments: GridCase.all)
    func alertButton(_ grid: GridCase) throws {
        var sim = GridSetup.prepare(grid)
        let target = grid.kind.ring
        try #require(sim.alerting.contains(target.id), "\(grid.kind) must be alerting before the press")
        let processBefore = sim.process
        let diskBefore = sim.disk
        let eventMark = sim.eventLog.count

        let action = sim.press(grid.button, on: target.id)
        #expect(action == AlertSpec.for(target.kind).action(for: grid.button))

        switch action {
        case .none?:
            expectNoAppAction(&sim, grid: grid, processBefore: processBefore, eventMark: eventMark)
        case .openToChallenge?:
            expectChallenge(&sim, grid: grid, diskBefore: diskBefore, eventMark: eventMark)
        case .confirmAwake?:
            expectConfirmed(&sim, grid: grid, processBefore: processBefore)
        case nil:
            Issue.record("the press did nothing")
        }
        expectClean(sim)
    }

    /// B2: no event; the next ring stays; a later open shows the D1 snoozed screen (or home after a nudge).
    func expectNoAppAction(_ sim: inout MorningSim, grid: GridCase, processBefore: ProcessState, eventMark: Int) {
        let target = grid.kind.ring
        #expect(!sim.events(since: eventMark).contains(where: isAlertAction))
        #expect(sim.process == processBefore)
        #expect(sim.state.finished[Std.today] == nil)
        if let next = grid.kind.nextLatched { #expect(sim.system.contains(next.id), "next ring \(next.kind) still live") }
        let wasForeground = sim.isForeground
        if !wasForeground { sim.open() }
        if target.kind == .nudge {
            let expected: Screen = wasForeground ? .ringing(target, sounding: true, snoozedUntil: nil) : .none
            #expect(sim.screen == expected)
        } else if grid.process == .staleChallenge {
            // S2 outranks S4: the challenge left open is shown, upgraded to the ring that just rang.
            #expect(sim.screen == .challenge(ActiveChallenge(ring: target, kind: .math)))
        } else if let next = grid.kind.nextLatched {
            #expect(sim.screen == .ringing(target, sounding: false, snoozedUntil: next.date))
        }
    }

    /// B3: the challenge for the latest due ring, at its level and snapshotted kind; B5: locked + cancel does nothing.
    func expectChallenge(_ sim: inout MorningSim, grid: GridCase, diskBefore: EngineState, eventMark: Int) {
        let target = grid.kind.ring
        let next = grid.kind.nextLatched
        if let next { #expect(sim.system.contains(next.id), "next ring \(next.kind) still live") }
        if grid.process == .lockedCancelUnlock {
            #expect(sim.events(since: eventMark).isEmpty)
            #expect(sim.process == .locked(cancelUnlock: true))
            #expect(sim.disk == diskBefore)
            sim.open()
            let until = target.allowsSnooze ? next?.date : nil
            #expect(sim.screen == .ringing(target, sounding: false, snoozedUntil: until))
            return
        }
        let expected = ActiveChallenge(ring: target, kind: .math)
        #expect(sim.isForeground)
        #expect(sim.screen == .challenge(expected))
        #expect(sim.state.challenge == expected)
        #expect(sim.disk.challenge == expected)
        #expect(sim.state.route == nil)
        #expect(sim.sound == .silent)
        if grid.process == .yesterdayChallenge {
            #expect(sim.state.finished[Std.ideal(day: 15)] == .missed)
        }
    }

    /// B4: the group is confirmed in the background; the other group still rings.
    func expectConfirmed(_ sim: inout MorningSim, grid: GridCase, processBefore: ProcessState) {
        let solvedAt = GridSetup.solvedAt
        let group = ids(Std.awakeGroup(0, solvedAt: solvedAt))
        let other = Std.awakeGroup(1, solvedAt: solvedAt)
        if case .foreground = processBefore {
            #expect(sim.process == processBefore)
        } else {
            #expect(!sim.isForeground)
        }
        #expect(sim.liveSystem(kind: .awakeCheck, morning: Std.today) == other)
        #expect(group.isSubset(of: sim.state.acknowledged))
        #expect(group.isSubset(of: sim.disk.acknowledged))
        #expect(group.isDisjoint(with: ids(sim.state.target)))
        if !sim.isForeground { sim.open() }
        #expect(sim.screen == .none)
    }
}

/// The pressed ring and what follows it.
enum GridKind: String, CaseIterable, Sendable {
    case nudge, main, snoozeL1, snoozeL2, deadline, guardRing, awakeCheck, awakeGuard

    var ring: Ring {
        switch self {
        case .nudge: Std.nudge(0)
        case .main: Std.main()
        case .snoozeL1: Std.snooze(0)
        case .snoozeL2: Std.snooze(1)
        case .deadline: Std.deadline()
        case .guardRing: Std.guardRing(7)
        case .awakeCheck: Std.awake(group: 0, index: 0, solvedAt: GridSetup.solvedAt)
        case .awakeGuard: Std.awake(group: 0, index: 1, solvedAt: GridSetup.solvedAt)
        }
    }

    var nextLatched: Ring? {
        switch self {
        case .nudge: Std.main()
        case .main: Std.snooze(0)
        case .snoozeL1: Std.snooze(1)
        case .snoozeL2: Std.snooze(2)
        case .deadline: Std.guardRing(1)
        case .guardRing: Std.guardRing(8)
        case .awakeCheck, .awakeGuard: nil
        }
    }

    var isAwake: Bool { self == .awakeCheck || self == .awakeGuard }

    /// The ring's kind, without building the ring (test discovery must not compute ids).
    var ringKind: RingKind {
        switch self {
        case .nudge: .nudge
        case .main: .main
        case .snoozeL1, .snoozeL2: .snooze
        case .deadline: .deadline
        case .guardRing: .guardRing
        case .awakeCheck, .awakeGuard: .awakeCheck
        }
    }
}

/// The process when the ring alerts (contract B5's list).
enum GridProcess: String, CaseIterable, Sendable {
    case killed, suspendedHome, foregroundHome, foregroundBedside, foregroundSheet
    /// Suspended with a lower-level challenge of this morning open.
    case staleChallenge
    /// Suspended since yesterday's challenge was left open (yesterday then ended as missed).
    case yesterdayChallenge
    case lockedCancelUnlock, lockedUnlock

    /// Bedside and sheets sit under the morning cover, so they can be up when a ring fires only after an
    /// in-app Snooze of the ring before it. From the Deadline on nothing dismisses the cover, so a guard never
    /// fires over them.
    func applies(to kind: GridKind) -> Bool {
        switch self {
        case .foregroundBedside, .foregroundSheet: kind != .guardRing
        case .staleChallenge: [.snoozeL2, .deadline, .guardRing].contains(kind)
        case .yesterdayChallenge: !kind.isAwake
        default: true
        }
    }
}

struct GridCase: Sendable, CustomTestStringConvertible {
    let kind: GridKind
    let button: AlertButton
    let process: GridProcess
    let order: IntentOrder

    var testDescription: String { "\(kind.rawValue) \(button.rawValue) \(process.rawValue) \(order)" }

    static let all: [GridCase] = GridKind.allCases.flatMap { kind in
        AlertButton.allCases.flatMap { button -> [GridCase] in
            if kind == .nudge && button == .secondary { return [] }
            let action = AlertSpec.for(kind.ringKind).action(for: button)
            let orders: [IntentOrder] = action == .openToChallenge ? IntentOrder.allCases : [.afterActive]
            return GridProcess.allCases.filter { $0.applies(to: kind) }.flatMap { process in
                orders.map { GridCase(kind: kind, button: button, process: process, order: $0) }
            }
        }
    }
}

/// Brings a standard sim to 10 s after the pressed ring started alerting, in the case's process state.
/// System alerts are not silenced by the app (audible = false), so the pressed ring is still alerting.
enum GridSetup {
    static let solvedAt = Std.t(6, 41)

    static func prepare(_ grid: GridCase) -> MorningSim {
        var sim = grid.process == .yesterdayChallenge ? yesterdayChallenge(grid) : MorningSim.armed(order: grid.order, audible: false)
        let target = grid.kind.ring
        if grid.kind.isAwake {
            sim.solveToday(at: solvedAt)
            enterAwake(&sim, grid.process)
        } else {
            if grid.process == .staleChallenge { openChallengeAtMain(&sim) }
            if grid.process == .lockedCancelUnlock && grid.kind == .guardRing {
                stopEveryRingWhileLocked(&sim, until: target.date.addingTimeInterval(-30))
            } else {
                sim.advanceStoppingSnoozes(to: target.date.addingTimeInterval(-30))
            }
            enter(&sim, grid.process)
        }
        sim.advance(to: target.date.addingTimeInterval(10))
        return sim
    }

    private static func yesterdayChallenge(_ grid: GridCase) -> MorningSim {
        var sim = MorningSim.armed(at: Std.t(6, 0, day: 15), order: grid.order, audible: false)
        sim.advance(to: Std.t(6, 40, 5, day: 15))
        sim.open()
        sim.tapStartChallenge(Std.main(of: Std.ideal(day: 15)).id)
        sim.suspend()
        return sim
    }

    /// Locked from before the deadline, the user presses Stop on every ring as it alerts and cancels Face ID
    /// each time, so only the pressed guard's predecessors have rung and none is still alerting.
    static func stopEveryRingWhileLocked(_ sim: inout MorningSim, until date: Date) {
        sim.advanceStoppingSnoozes(to: Std.t(7, 9, 30))
        sim.lock(cancelUnlock: true)
        while sim.now < date {
            sim.advance(to: min(date, sim.system.nextFireDate(after: sim.now) ?? date))
            for id in sim.alerting.sorted(by: { $0.uuidString < $1.uuidString }) { sim.press(.stop, on: id) }
        }
    }

    private static func openChallengeAtMain(_ sim: inout MorningSim) {
        sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
        sim.open()
        sim.advance(to: Std.t(6, 40, 5))
        sim.tapStartChallenge(Std.main().id)
        sim.suspend()
    }

    private static func enter(_ sim: inout MorningSim, _ process: GridProcess) {
        switch process {
        case .killed: sim.kill()
        case .suspendedHome, .staleChallenge, .yesterdayChallenge: break
        case .foregroundHome: sim.open()
        case .foregroundBedside: openUnderCover(&sim, to: .bedside)
        case .foregroundSheet: openUnderCover(&sim, to: .sheet(.settings))
        case .lockedCancelUnlock: sim.lock(cancelUnlock: true)
        case .lockedUnlock: sim.lock(cancelUnlock: false)
        }
    }

    /// Opens the app and, when the D1 "Snoozed until" screen of the ring before is up, snoozes it in-app so
    /// the home surface (Bedside or a sheet) can be shown.
    static func openUnderCover(_ sim: inout MorningSim, to surface: ForegroundSurface) {
        sim.open()
        if case .ringing(let ring, _, _) = sim.screen, ring.allowsSnooze { sim.tapSnooze(ring.id) }
        sim.show(surface)
    }

    private static func enterAwake(_ sim: inout MorningSim, _ process: GridProcess) {
        switch process {
        case .killed: sim.kill()
        case .suspendedHome: sim.suspend()
        case .foregroundHome: sim.closeReleased()
        case .foregroundBedside:
            sim.closeReleased()
            sim.show(.bedside)
        case .foregroundSheet:
            sim.closeReleased()
            sim.show(.sheet(.settings))
        case .lockedCancelUnlock: sim.lock(cancelUnlock: true)
        case .lockedUnlock: sim.lock(cancelUnlock: false)
        case .staleChallenge, .yesterdayChallenge: sim.suspend()
        }
    }
}
