import Foundation
import Testing
@testable import WakelatchCore

@Suite("MorningUnderWay")
struct MorningUnderWayTests {
    let morning = Date(timeIntervalSince1970: 1_800_000_000) // Ideal
    func at(_ minutes: Double) -> Date { morning.addingTimeInterval(minutes * 60) }

    var rings: [MorningRing] {
        [MorningRing(morning: morning, date: at(-20), latched: false),
         MorningRing(morning: morning, date: at(-10), latched: false),
         MorningRing(morning: morning, date: at(0), latched: true),
         MorningRing(morning: morning, date: at(30), latched: true)]
    }

    @Test("before the first ring, nothing is under way")
    func beforeFirstRing() {
        #expect(MorningUnderWay.find(in: rings, now: at(-21)) == nil)
    }

    @Test("after a nudge rang, the morning is under way so its later rings are kept")
    func afterNudge() {
        #expect(MorningUnderWay.find(in: rings, now: at(-19)) == morning)
        #expect(MorningUnderWay.find(in: rings, now: at(-1)) == morning)
    }

    @Test("during the latch the morning is under way")
    func duringLatch() {
        #expect(MorningUnderWay.find(in: rings, now: at(15)) == morning)
    }

    @Test("ten minutes after the last latched ring it is over")
    func over() {
        #expect(MorningUnderWay.find(in: rings, now: at(39)) == morning)
        #expect(MorningUnderWay.find(in: rings, now: at(41)) == nil)
    }
}
