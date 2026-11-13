import Foundation
import Testing
@testable import WakelatchCore

@Suite("GuardChain")
struct GuardChainTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("first ring is the start time, guards follow at the interval")
    func fireDates() throws {
        let chain = try GuardChain(firstFire: start, interval: 60, guardCount: 3)
        #expect(chain.fireDates == [
            start,
            start.addingTimeInterval(60),
            start.addingTimeInterval(120),
            start.addingTimeInterval(180),
        ])
    }

    @Test("zero guards means a single ring")
    func noGuards() throws {
        let chain = try GuardChain(firstFire: start, interval: 60, guardCount: 0)
        #expect(chain.fireDates == [start])
    }

    @Test("last ring is the end of the chain")
    func lastFire() throws {
        let chain = try GuardChain(firstFire: start, interval: 90, guardCount: 10)
        #expect(chain.lastFire == start.addingTimeInterval(900))
    }

    @Test("interval below 30 s is rejected")
    func shortInterval() {
        #expect(throws: GuardChain.Error.intervalTooShort) {
            try GuardChain(firstFire: start, interval: 29, guardCount: 3)
        }
    }

    @Test("negative guard count is rejected")
    func negativeCount() {
        #expect(throws: GuardChain.Error.negativeGuardCount) {
            try GuardChain(firstFire: start, interval: 60, guardCount: -1)
        }
    }

    @Test("rings still due after a moment drop the ones already past")
    func remaining() throws {
        let chain = try GuardChain(firstFire: start, interval: 60, guardCount: 3)
        let now = start.addingTimeInterval(61)
        #expect(chain.fireDates(after: now) == [
            start.addingTimeInterval(120),
            start.addingTimeInterval(180),
        ])
    }
}
