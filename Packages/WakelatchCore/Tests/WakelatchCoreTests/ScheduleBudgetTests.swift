import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract A7 and owner decision D2: at most 250 alarms; trim the farthest morning's latest guards first,
/// never the next morning's.
@Suite("A7: ScheduleBudget.trim")
struct ScheduleBudgetTests {
    /// A 3-hour morning: 27 rings before the guards (2 nudges, main, 23 snoozes, deadline) and 60 guards.
    func bigMorning(day: Int) -> [Ring] {
        let ideal = Std.t(5, 0, day: day)
        let early = (0..<27).map {
            Ring(id: UUID(), date: ideal.addingTimeInterval(Double($0) * 400 - 1200), kind: $0 < 2 ? .nudge : .snooze,
                 level: 1, morning: ideal, challenge: .math)
        }
        let guards = (1...60).map {
            Ring(id: UUID(), date: ideal.addingTimeInterval(10_800 + Double($0) * 60), kind: .guardRing, level: 3,
                 morning: ideal, challenge: .math)
        }
        return early + guards
    }

    func guards(_ rings: [Ring]) -> [Ring] { rings.filter { $0.kind == .guardRing } }

    @Test("under the limit nothing is trimmed")
    func underLimit() {
        let mornings = [bigMorning(day: 16), bigMorning(day: 17)]
        #expect(ScheduleBudget.trim(mornings, reserved: 8) == mornings)
    }

    @Test("261 rings: the farthest morning loses exactly its 11 latest guards; nearer mornings are untouched")
    func trimFarthestLatestGuards() {
        let (a, b, c) = (bigMorning(day: 16), bigMorning(day: 17), bigMorning(day: 18))
        let kept = ScheduleBudget.trim([a, b, c], reserved: 0).flatMap { $0 }
        let expected = a + b + c.dropLast(11)
        #expect(Set(kept.map(\.id)) == Set(expected.map(\.id)))
        #expect(kept.count == 250)
    }

    @Test("over by 91: the farthest morning loses all 60 guards, then the middle one its latest 31")
    func trimIntoMiddleMorning() {
        let (a, b, c) = (bigMorning(day: 16), bigMorning(day: 17), bigMorning(day: 18))
        let kept = ScheduleBudget.trim([a, b, c], reserved: 80).flatMap { $0 }
        let expected = a + b.dropLast(31) + c.filter { $0.kind != .guardRing }
        #expect(Set(kept.map(\.id)) == Set(expected.map(\.id)))
        #expect(kept.count + 80 == 250)
        let removed = Set((a + b + c).map(\.id)).subtracting(kept.map(\.id))
        #expect(removed.isSubset(of: Set(guards(b + c).map(\.id))))
    }

    @Test("when guard trimming is not enough, whole mornings are dropped farthest first; the next morning stays whole")
    func dropWholeMornings() {
        let (a, b, c) = (bigMorning(day: 16), bigMorning(day: 17), bigMorning(day: 18))
        let kept = ScheduleBudget.trim([a, b, c], reserved: 150).flatMap { $0 }
        #expect(Set(kept.map(\.id)) == Set(a.map(\.id)))
    }

    @Test("the first (next) morning is never trimmed, even when it alone is over the limit")
    func firstMorningNeverTrimmed() {
        let a = bigMorning(day: 16)
        let result = ScheduleBudget.trim([a], reserved: 200)
        #expect(result.first == a)
        #expect(result.flatMap { $0 } == a)
    }

    @Test("kept rings stay in their mornings' order, nearest first")
    func orderKept() {
        let (a, b, c) = (bigMorning(day: 16), bigMorning(day: 17), bigMorning(day: 18))
        let result = ScheduleBudget.trim([a, b, c], reserved: 0)
        #expect(result.count == 3)
        #expect(result[0] == a)
        #expect(result[1] == b)
        #expect(result[2] == Array(c.dropLast(11)))
    }

    @Test("a lower limit trims to that limit")
    func customLimit() {
        let (a, b) = (bigMorning(day: 16), bigMorning(day: 17))
        let kept = ScheduleBudget.trim([a, b], reserved: 0, limit: 150).flatMap { $0 }
        #expect(kept.count == 150)
        #expect(Set(kept.map(\.id)) == Set((a + b.dropLast(24)).map(\.id)))
    }
}
