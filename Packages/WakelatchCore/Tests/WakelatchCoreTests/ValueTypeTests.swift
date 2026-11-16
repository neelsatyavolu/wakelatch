import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Small value types the engine and views share: records, snapshots, screens and challenge copy.
@Suite("Value types")
struct ValueTypeTests {
    @Test("MorningRecord: ideal is the morning; skipped and the up-by flags follow outcome and upAt")
    func record() {
        let skipped = MorningRecord(morning: Std.today, deadline: Std.t(7, 10), outcome: .skipped, upAt: nil)
        #expect(skipped.ideal == Std.today)
        #expect(skipped.skipped)
        #expect(!skipped.upByIdeal)
        #expect(!skipped.upByDeadline)
        let late = MorningRecord(morning: Std.today, deadline: Std.t(7, 10), outcome: .solved, upAt: Std.t(7, 12))
        #expect(!late.skipped)
        #expect(!late.upByIdeal)
        #expect(!late.upByDeadline)
    }

    @Test("ChallengeSnapshot: main and snoozes carry the snooze kind, deadline and guards the deadline kind")
    func snapshot() {
        let snapshot = ChallengeSnapshot(snooze: .steps, deadline: .shake)
        #expect(snapshot.kind(for: .main) == .steps)
        #expect(snapshot.kind(for: .snooze) == .steps)
        #expect(snapshot.kind(for: .deadline) == .shake)
        #expect(snapshot.kind(for: .guardRing) == .shake)
        #expect(snapshot.kind(for: .nudge) == nil)
        #expect(snapshot.kind(for: .awakeCheck) == nil)
    }

    @Test("Screen.isShowing is false only for home")
    func screenShowing() {
        #expect(!Screen.none.isShowing)
        #expect(Screen.ringing(Std.main(), sounding: false, snoozedUntil: nil).isShowing)
    }

    @Test("Challenge kinds: ids, goals and summaries at every level")
    func challengeCopy() {
        #expect(ChallengeKind.allCases.map(\.id) == ChallengeKind.allCases.map(\.rawValue))
        #expect(ChallengeKind.phrase.goal(level: 2) == 1)
        #expect(ChallengeKind.shake.goal(level: 3) == 35)
        #expect(ChallengeKind.phrase.summary(level: 1) == "A short sentence")
        #expect(ChallengeKind.eyesOpen.summary(level: 2) == "Keep your eyes open for 30 seconds")
        #expect(ChallengeKind.steps.summary(level: 3) == "Walk 60 steps")
        #expect(ChallengeKind.shake.summary(level: 1) == "Shake the phone 15 times")
    }

    @Test("ClockTime orders by minutes since midnight; old planner rings report snooze")
    func clockTimeAndPlannedRing() throws {
        #expect(ClockTime(hour: 6, minute: 40) < ClockTime(hour: 7, minute: 0))
        #expect(!(ClockTime(hour: 7, minute: 0) < ClockTime(hour: 6, minute: 40)))
        let times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
        let rings = try MorningPlan.build(on: Std.today, times: times, options: PlanOptions(), calendar: Std.calendar)
        #expect(rings.filter(\.allowsSnooze).map(\.kind) == [.main, .snooze, .snooze, .snooze])
        let days = MorningPlan.upcomingDays(after: Std.t(6, 25), times: times, repeatDays: [], count: 1,
                                            nudges: false, calendar: Std.calendar)
        #expect(days == [Std.calendar.startOfDay(for: Std.today)])
    }

    @Test("MorningUnderWay: a morning with only nudges ends grace after its last nudge")
    func underWayWithoutLatched() {
        let rings = [MorningRing(morning: Std.today, date: Std.t(6, 20), latched: false),
                     MorningRing(morning: Std.today, date: Std.t(6, 30), latched: false)]
        #expect(MorningUnderWay.find(in: rings, now: Std.t(6, 35)) == Std.today)
        #expect(MorningUnderWay.find(in: rings, now: Std.t(6, 41)) == nil)
    }
}
