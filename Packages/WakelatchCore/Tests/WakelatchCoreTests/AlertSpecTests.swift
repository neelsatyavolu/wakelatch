import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Contract B1: the buttons of each system alert.
@Suite("B1: AlertSpec")
struct AlertSpecTests {
    @Test("nudge: 'Ideal time soon', Stop does nothing in the app, no secondary button")
    func nudge() {
        let spec = AlertSpec.for(.nudge)
        #expect(spec.title == "Wakelatch. Ideal time soon.")
        #expect(spec.secondaryLabel == nil)
        #expect(spec.action(for: .stop) == AlertAction.none)
        #expect(spec.action(for: .secondary) == AlertAction.none)
    }

    @Test("main and snooze: Stop is the system snooze, 'I'm up' opens the challenge", arguments: [RingKind.main, .snooze])
    func snoozable(kind: RingKind) {
        let spec = AlertSpec.for(kind)
        #expect(spec.title == "Wakelatch. Stop to snooze.")
        #expect(spec.secondaryLabel == "I'm up")
        #expect(spec.action(for: .stop) == AlertAction.none)
        #expect(spec.action(for: .secondary) == .openToChallenge)
    }

    @Test("deadline and guard: both Stop and 'Solve' open the challenge", arguments: [RingKind.deadline, .guardRing])
    func latchedAfterDeadline(kind: RingKind) {
        let spec = AlertSpec.for(kind)
        #expect(spec.title == "Wakelatch. Deadline. Solve to stop.")
        #expect(spec.secondaryLabel == "Solve")
        #expect(spec.action(for: .stop) == .openToChallenge)
        #expect(spec.action(for: .secondary) == .openToChallenge)
    }

    @Test("awake check: both Stop and 'I'm up' confirm in the background")
    func awakeCheck() {
        let spec = AlertSpec.for(.awakeCheck)
        #expect(spec.title == "Wakelatch. Still up?")
        #expect(spec.secondaryLabel == "I'm up")
        #expect(spec.action(for: .stop) == .confirmAwake)
        #expect(spec.action(for: .secondary) == .confirmAwake)
    }

    @Test("only deadline and guard rings open the app from Stop", arguments: RingKind.allCases)
    func stopOpensOnlyAfterDeadline(kind: RingKind) {
        let opens = AlertSpec.for(kind).action(for: .stop) == .openToChallenge
        #expect(opens == (kind == .deadline || kind == .guardRing))
    }

    @Test("every kind with a secondary label also has a symbol", arguments: RingKind.allCases)
    func symbols(kind: RingKind) {
        let spec = AlertSpec.for(kind)
        #expect((spec.secondaryLabel == nil) == (spec.secondarySymbol == nil))
    }
}
