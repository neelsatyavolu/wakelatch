import Foundation
import Testing
@testable import WakelatchCore

@Suite("dueRing")
struct DueRingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var rings: [Date] { [t0, t0.addingTimeInterval(60), t0.addingTimeInterval(120)] }

    @Test("nothing is due before the first ring")
    func beforeFirst() {
        #expect(GuardChain.dueRing(in: rings, at: t0.addingTimeInterval(-1)) == nil)
    }

    @Test("the first ring is due at its own time")
    func atFirst() {
        #expect(GuardChain.dueRing(in: rings, at: t0) == 0)
    }

    @Test("the latest past ring is the one due")
    func between() {
        #expect(GuardChain.dueRing(in: rings, at: t0.addingTimeInterval(61)) == 1)
    }

    @Test("after the last ring the last one stays due")
    func afterLast() {
        #expect(GuardChain.dueRing(in: rings, at: t0.addingTimeInterval(3600)) == 2)
    }

    @Test("an empty chain has nothing due")
    func empty() {
        #expect(GuardChain.dueRing(in: [], at: t0) == nil)
    }
}
