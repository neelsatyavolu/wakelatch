import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group F, generated (plan 2.5): a ring starts alerting while the app is in the foreground, for every ring
/// kind x audible x what is on screen. Checks takeover (F3), the open challenge silencing (F4), no silence
/// behind a hidden cover (F5, INV9), sheets dismissed first (F6) and the chime (F1).
@Suite("F grid: a ring alerts in the foreground, every kind x audible x screen")
struct AlertingGridTests {
    @Test("F grid: the screen, silencing and chime follow F1-F6", arguments: AlertingCase.all)
    func alerting(_ grid: AlertingCase) throws {
        var sim = AlertingSetup.prepare(grid)
        let ring = grid.kind.ring
        try #require(sim.isForeground)
        try #require(!sim.system.alerting.contains(ring.id), "set up before \(ring.kind) fires")
        let surfaceBefore = sim.process
        let mark = sim.effectLog.count
        let screenBefore = sim.screen
        sim.advance(to: ring.date.addingTimeInterval(1))

        #expect(sim.screen == grid.expectedScreen)
        let silenced = sim.effects(since: mark).contains(.silence(ring.id))
        #expect(silenced == grid.silences, "silence of \(ring.kind)")
        #expect(sim.alerting.contains(ring.id) == !grid.silences)
        #expect(sim.sound == grid.expectedSound)
        if screenBefore == .none {
            #expect(sim.effects(since: mark).contains(.dismissHomeSheets), "F6")
        }
        if case .foreground(.sheet) = surfaceBefore { #expect(sim.process == .foreground(.home), "F6: sheet closed") }
        expectClean(sim)
    }
}

/// What is on screen (and which home surface) when the ring fires.
enum AlertingScreen: String, CaseIterable, Sendable {
    /// Foreground on home: nothing, or the cover the morning already shows (a guard's "Solve").
    case home
    case bedside
    case sheet
    /// The challenge of the same morning, opened at the main ring and in use (typed into 10 s before the
    /// ring). An idle challenge is in ReviewFixTests.
    case challenge
    /// Released after the solve, left up.
    case released
    /// The awake check of the same morning, left unanswered.
    case awakeCheck

    func applies(to kind: GridKind) -> Bool {
        switch (self, kind) {
        case (.home, .awakeGuard), (.bedside, .awakeGuard), (.sheet, .awakeGuard): false
        case (.bedside, .guardRing), (.sheet, .guardRing): false
        case (.home, _), (.bedside, _), (.sheet, _): true
        case (.challenge, _): [.snoozeL1, .snoozeL2, .deadline, .guardRing].contains(kind)
        case (.released, _): kind == .awakeCheck
        case (.awakeCheck, _): kind == .awakeGuard
        }
    }
}

struct AlertingCase: Sendable, CustomTestStringConvertible {
    let kind: GridKind
    let audible: Bool
    let screen: AlertingScreen

    var testDescription: String { "\(kind.rawValue) audible \(audible) over \(screen.rawValue)" }

    static let all: [AlertingCase] = GridKind.allCases.flatMap { kind in
        [true, false].flatMap { audible in
            AlertingScreen.allCases.filter { $0.applies(to: kind) }
                .map { AlertingCase(kind: kind, audible: audible, screen: $0) }
        }
    }

    /// S2/C3 for an open challenge (it upgrades only to a higher level: main's for an L1 snooze, the
    /// deadline's for a guard), S3 for awake checks, S4/S5 otherwise.
    var expectedScreen: Screen {
        let ring = kind.ring
        if kind.isAwake { return .awakeCheck(ring) }
        if screen == .challenge {
            let opened: Ring = switch kind {
            case .snoozeL1: Std.main()
            case .guardRing: Std.deadline()
            default: ring
            }
            return .challenge(ActiveChallenge(ring: opened, kind: .math))
        }
        return .ringing(ring, sounding: true, snoozedUntil: nil)
    }

    /// F4: an open challenge in use silences the morning's alerts at any volume. F3: a sounding ringing screen takes
    /// the alert over only when audible. Awake checks are never silenced: the system alarm is their sound.
    var silences: Bool {
        if kind.isAwake { return false }
        return screen == .challenge || audible
    }

    var expectedSound: SimSound {
        if case .ringing(let ring, sounding: true, _) = expectedScreen { return .playing(nudge: ring.kind == .nudge) }
        return .silent
    }
}

/// Brings a standard sim to 30 s before the case's ring, foreground on the case's screen.
enum AlertingSetup {
    static func prepare(_ grid: AlertingCase) -> MorningSim {
        var sim = MorningSim.armed(audible: grid.audible)
        let before = grid.kind.ring.date.addingTimeInterval(-30)
        if grid.kind.isAwake {
            awake(&sim, grid, before: before)
        } else if grid.screen == .challenge {
            sim.advanceStoppingSnoozes(to: Std.t(6, 39, 50))
            sim.open()
            sim.advance(to: Std.t(6, 40, 5))
            sim.tapStartChallenge(Std.main().id)
            sim.advance(to: grid.kind.ring.date.addingTimeInterval(-10))
            sim.send(.challengeActivity(now: sim.now))
        } else if grid.kind == .guardRing {
            GridSetup.stopEveryRingWhileLocked(&sim, until: before)
            sim.open()
        } else {
            sim.advanceStoppingSnoozes(to: before)
            GridSetup.openUnderCover(&sim, to: surface(grid.screen))
        }
        return sim
    }

    private static func awake(_ sim: inout MorningSim, _ grid: AlertingCase, before: Date) {
        sim.solveToday(at: GridSetup.solvedAt)
        switch grid.screen {
        case .released, .awakeCheck: break
        default:
            sim.closeReleased()
            sim.show(surface(grid.screen))
        }
        sim.advance(to: before)
    }

    private static func surface(_ screen: AlertingScreen) -> ForegroundSurface {
        switch screen {
        case .bedside: .bedside
        case .sheet: .sheet(.settings)
        default: .home
        }
    }
}
