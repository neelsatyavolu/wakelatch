import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract T2-T6: timing presets, levels and snapshotted challenge kinds.
@Suite("T: PlanTiming and one morning's rings")
struct PlanTimingTests {
    let math = ChallengeSnapshot(snooze: .math, deadline: .math)
    let production = PlanTiming.production(PlanOptions())

    @Test("T2: production timing is nudges -20/-10 min, 9 min snoozes, 60 guards a minute apart, 10 min grace")
    func productionValues() {
        let t = production
        #expect(t.nudgeOffsets == [1200, 600])
        #expect(t.snoozeSpacing == 540)
        #expect(t.maxSnoozes == 24)
        #expect(t.snoozeDeadlineGap == 60)
        #expect(t.guardSpacing == 60)
        #expect(t.guardWindow == 3600)
        #expect(t.guardCount == 60)
        #expect(t.grace == 600)
        #expect(t.awakeOffsets == [300, 720])
        #expect(t.awakeGuards == 3)
        #expect(t.awakeGuardSpacing == 60)
        #expect(t.awakeCheckExpiry == 900)
        #expect(t.windowOverride == nil)
        #expect(t.routeMaxAge == 120)
        #expect(t.nudgeScreenCap == 300)
        #expect(t.releasedKeepAwake == 60)
    }

    @Test("T2: nudges off gives no nudge offsets and no nudge rings")
    func nudgesOff() {
        let timing = PlanTiming.production(PlanOptions(nudges: false))
        #expect(timing.nudgeOffsets.isEmpty)
        let rings = MorningPlan.build(morning: Std.today, window: Std.window, timing: timing, challenges: math)
        #expect(rings == Std.morning(nudges: false))
    }

    @Test("T2 (D2): options.guardRings is ignored, production always plans 60 guards", arguments: [0, 3, 15, 200])
    func guardRingsIgnored(guardRings: Int) {
        let timing = PlanTiming.production(PlanOptions(guardRings: guardRings))
        #expect(timing.guardCount == 60)
        let rings = MorningPlan.build(morning: Std.today, window: Std.window, timing: timing, challenges: math)
        #expect(rings.filter { $0.kind == .guardRing } == Std.guards())
    }

    @Test("T2: a snooze interval under 3 minutes is clamped to 3 minutes")
    func snoozeClamp() {
        #expect(PlanTiming.production(PlanOptions(snoozeMinutes: 1)).snoozeSpacing == 180)
    }

    @Test("T2, T4: the standard morning is exactly nudges, main, three snoozes (L1, L2, L2), deadline, 60 guards")
    func standardMorning() {
        let rings = MorningPlan.build(morning: Std.today, window: Std.window, timing: production, challenges: math)
        #expect(rings == Std.morning())
        #expect(rings.count == 67)
        #expect(rings.map(\.date) == rings.map(\.date).sorted())
    }

    @Test("T4: nudges are level 0, main 1, snoozes 1 in the first half of the window and 2 after, deadline and guards 3")
    func levels() {
        let rings = MorningPlan.build(morning: Std.today, window: 3600, timing: production, challenges: math)
        for ring in rings {
            switch ring.kind {
            case .nudge: #expect(ring.level == 0)
            case .main: #expect(ring.level == 1)
            case .snooze:
                let offset = ring.date.timeIntervalSince(Std.today)
                #expect(ring.level == (2 * offset <= 3600 ? 1 : 2), "snooze at +\(offset)")
            case .deadline, .guardRing: #expect(ring.level == 3)
            case .awakeCheck: Issue.record("a morning plan never contains awake checks")
            }
        }
        // 60-minute window, 9-minute spacing: +9, +18, +27 are L1; +36, +45, +54 are L2.
        #expect(rings.filter { $0.kind == .snooze }.map(\.level) == [1, 1, 1, 2, 2, 2])
    }

    @Test("T5: main and snoozes carry the snooze kind, deadline and guards the deadline kind, nudges none")
    func snapshotKinds() {
        let rings = MorningPlan.build(morning: Std.today, window: Std.window, timing: production,
                                      challenges: ChallengeSnapshot(snooze: .phrase, deadline: .shake))
        #expect(rings == Std.morning(snooze: .phrase, deadline: .shake))
        #expect(rings.filter { $0.kind == .nudge }.allSatisfy { $0.challenge == nil })
    }

    @Test("T2: a snooze less than 60 s before the deadline is dropped")
    func crowdedSnoozeDropped() {
        // 18.5-minute window: +9 min is kept (L1), +18 min is 30 s before the deadline and dropped.
        let rings = MorningPlan.build(morning: Std.today, window: 1110, timing: production, challenges: math)
        #expect(rings.filter { $0.kind == .snooze }.map(\.date) == [Std.today.addingTimeInterval(540)])
        #expect(rings.first { $0.kind == .deadline }?.date == Std.today.addingTimeInterval(1110))
    }

    @Test("T2: a 3-hour window widens snooze spacing to 7.5 min so there are at most 24 snoozes")
    func longWindowWidensSpacing() {
        let timing = PlanTiming.production(PlanOptions(snoozeMinutes: 3))
        let rings = MorningPlan.build(morning: Std.today, window: 10_800, timing: timing, challenges: math)
        let snoozes = rings.filter { $0.kind == .snooze }
        #expect(snoozes.count == 23)
        #expect(snoozes.count <= timing.maxSnoozes)
        #expect(snoozes.map(\.date) == (1...23).map { Std.today.addingTimeInterval(Double($0) * 450) })
        #expect(snoozes.map(\.level) == Array(repeating: 1, count: 12) + Array(repeating: 2, count: 11))
        #expect(rings.count == 87)
    }

    @Test("T6: a window of 0 gives no main and no snoozes, only nudges, the deadline at Ideal and its guards")
    func zeroWindow() {
        let rings = MorningPlan.build(morning: Std.today, window: 0, timing: production, challenges: math)
        #expect(rings.filter { $0.kind == .main || $0.kind == .snooze }.isEmpty)
        let deadline = Ring(date: Std.today, kind: .deadline, level: 3, morning: Std.today, challenge: .math)
        #expect(rings.filter { $0.kind == .deadline } == [deadline])
        #expect(rings.filter { $0.kind == .guardRing }.count == 60)
        #expect(rings.filter { $0.kind == .nudge } == [Std.nudge(0), Std.nudge(1)])
    }

    @Test("T3: the compressed profile is nudges -40/-20 s, snoozes +40 (L1) and +80 (L2), deadline +120, guards +145/+170/+195")
    func compressedMorning() {
        let launch = Std.t(6, 0)
        let ideal = launch.addingTimeInterval(60)
        let timing = PlanTiming.compressed
        #expect(timing.windowOverride == 120)
        #expect(timing.guardCount == 3)
        #expect(timing.grace == 30)
        let rings = MorningPlan.build(morning: ideal, window: 120, timing: timing, challenges: math)
        let shape = rings.map { Shape(offset: $0.date.timeIntervalSince(ideal), kind: $0.kind, level: $0.level) }
        #expect(shape == [
            Shape(offset: -40, kind: .nudge, level: 0), Shape(offset: -20, kind: .nudge, level: 0),
            Shape(offset: 0, kind: .main, level: 1),
            Shape(offset: 40, kind: .snooze, level: 1), Shape(offset: 80, kind: .snooze, level: 2),
            Shape(offset: 120, kind: .deadline, level: 3),
            Shape(offset: 145, kind: .guardRing, level: 3), Shape(offset: 170, kind: .guardRing, level: 3),
            Shape(offset: 195, kind: .guardRing, level: 3),
        ])
    }

    @Test("T3: compressed with nudgeOffsets = [] is the no-nudge profile")
    func compressedNoNudges() {
        var timing = PlanTiming.compressed
        timing.nudgeOffsets = []
        let ideal = Std.t(6, 1)
        let rings = MorningPlan.build(morning: ideal, window: 120, timing: timing, challenges: math)
        #expect(rings.allSatisfy { $0.kind != .nudge })
        #expect(rings.first?.kind == .main)
        #expect(rings.count == 7)
    }

    @Test("T3: compressed awake checks are solve+30 and solve+70, each with 2 guards 20 s apart")
    func compressedAwakeChecks() {
        let solved = Std.t(6, 3)
        let rings = MorningPlan.awakeChecks(morning: Std.t(6, 1), solvedAt: solved, timing: .compressed)
        let shape = rings.map { [$0.date.timeIntervalSince(solved), Double($0.checkGroup ?? -1)] }
        #expect(Set(shape) == [[30, 0], [50, 0], [70, 0], [70, 1], [90, 1], [110, 1]])
        #expect(Set(rings.map(\.id)).count == 6)
        #expect(rings.allSatisfy { $0.kind == .awakeCheck && $0.level == 0 && $0.challenge == nil })
    }

    @Test("W1: production awake checks are solve+5 and solve+12 min, each followed by 3 guards a minute apart")
    func productionAwakeChecks() {
        let solved = Std.t(6, 41)
        let rings = MorningPlan.awakeChecks(morning: Std.today, solvedAt: solved, timing: production)
        #expect(rings.sorted { $0.date < $1.date } == Std.awakeChecks(solvedAt: solved))
    }
}

struct Shape: Hashable, CustomStringConvertible {
    let offset: TimeInterval
    let kind: RingKind
    let level: Int

    var description: String { "\(kind)@\(Int(offset))s L\(level)" }
}
