import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract I1, I2: deterministic, name-based ring ids.
@Suite("I: RingIdentity")
struct RingIdentityTests {
    let morning = Std.today
    let date = Std.t(7, 11)

    @Test("I1: the id is a version-5 (SHA-1, name-based) RFC 4122 UUID")
    func versionFive() {
        let id = RingIdentity.id(morning: morning, kind: .guardRing, date: date, group: nil, level: 0, challenge: nil)
        #expect(id.uuid.6 >> 4 == 5)
        #expect(id.uuid.8 & 0xC0 == 0x80)
        #expect(RingIdentity.version == "v2")
    }

    @Test("I2: the same inputs always give the same id")
    func deterministic() {
        let a = RingIdentity.id(morning: morning, kind: .snooze, date: Std.t(6, 49), group: nil, level: 0, challenge: nil)
        let b = RingIdentity.id(morning: morning, kind: .snooze, date: Std.t(6, 49), group: nil, level: 0, challenge: nil)
        #expect(a == b)
    }

    @Test("I2: changing the morning, kind, date or group changes the id")
    func everyFieldCounts() {
        let base = RingIdentity.id(morning: morning, kind: .awakeCheck, date: date, group: 0, level: 0, challenge: nil)
        let variants = [
            RingIdentity.id(morning: Std.ideal(day: 17), kind: .awakeCheck, date: date, group: 0, level: 0, challenge: nil),
            RingIdentity.id(morning: morning, kind: .guardRing, date: date, group: 0, level: 0, challenge: nil),
            RingIdentity.id(morning: morning, kind: .awakeCheck, date: date.addingTimeInterval(1), group: 0, level: 0, challenge: nil),
            RingIdentity.id(morning: morning, kind: .awakeCheck, date: date, group: 1, level: 0, challenge: nil),
            RingIdentity.id(morning: morning, kind: .awakeCheck, date: date, group: nil, level: 0, challenge: nil),
        ]
        #expect(!variants.contains(base))
        #expect(Set(variants).count == variants.count)
    }

    @Test("I1: every kind gives a distinct id for the same instant", arguments: RingKind.allCases)
    func kindDistinct(kind: RingKind) {
        let others = RingKind.allCases.filter { $0 != kind }.map {
            RingIdentity.id(morning: morning, kind: $0, date: date, group: nil, level: 0, challenge: nil)
        }
        #expect(!others.contains(RingIdentity.id(morning: morning, kind: kind, date: date, group: nil, level: 0, challenge: nil)))
    }

    @Test("I1: Ring(date:kind:...) takes its id from RingIdentity")
    func ringUsesIdentity() {
        let ring = Ring(date: date, kind: .guardRing, level: 3, morning: morning, challenge: .math)
        #expect(ring.id == RingIdentity.id(morning: morning, kind: .guardRing, date: date, group: nil, level: 3,
                                           challenge: .math))
        let check = Ring(date: date, kind: .awakeCheck, level: 0, morning: morning, checkGroup: 1)
        #expect(check.id == RingIdentity.id(morning: morning, kind: .awakeCheck, date: date, group: 1, level: 0, challenge: nil))
    }

    @Test("I2, I3: level and challenge kind are hashed, so changed metadata always gets a new id (review 9)")
    func levelAndKindHashed() {
        let a = Ring(date: date, kind: .guardRing, level: 3, morning: morning, challenge: .math)
        let b = Ring(date: date, kind: .guardRing, level: 3, morning: morning, challenge: .shake)
        let c = Ring(date: date, kind: .snooze, level: 1, morning: morning, challenge: .math)
        let d = Ring(date: date, kind: .snooze, level: 2, morning: morning, challenge: .math)
        #expect(a.id != b.id)
        #expect(c.id != d.id)
    }
}
