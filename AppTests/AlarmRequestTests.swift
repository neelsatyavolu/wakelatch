import AppIntents
import Foundation
import Testing
@testable import Wakelatch
import WakelatchCore

/// What each system alert carries (plan Shell03, Shell04), and the ledger that rebuilds rings from AlarmKit.
@MainActor
struct AlarmRequestTests {
    private let morning = Date(timeIntervalSince1970: 1_767_600_000)

    private func ring(_ kind: RingKind) -> Ring {
        let level = switch kind {
        case .nudge, .awakeCheck: 0
        case .main, .snooze: 1
        case .deadline, .guardRing: 3
        }
        return Ring(date: morning.addingTimeInterval(60), kind: kind, level: level, morning: morning,
                    checkGroup: kind == .awakeCheck ? 1 : nil,
                    challenge: kind.latched ? .phrase : nil)
    }

    /// The intent an alert action runs, by type, and the ring id it carries.
    private func describe(_ intent: (any LiveActivityIntent)?) -> (AlertAction, String?) {
        guard let intent else { return (.none, nil) }
        switch intent {
        case let open as OpenToChallengeIntent: return (AlertAction.openToChallenge, open.alarmID)
        case let confirm as ConfirmAwakeIntent: return (AlertAction.confirmAwake, confirm.alarmID)
        default: return (AlertAction.none, nil)
        }
    }

    @Test(arguments: RingKind.allCases)
    func shell03_alertMatchesAlertSpec(kind: RingKind) {
        let ring = ring(kind)
        let spec = AlertSpec.for(kind)
        let request = AlarmRequest.make(for: ring, silent: false)
        #expect(request.title == spec.title)
        #expect(request.secondaryLabel == spec.secondaryLabel)
        #expect(request.secondarySymbol == spec.secondarySymbol)

        let stop = describe(request.stopIntent)
        #expect(stop.0 == spec.action(for: .stop))
        #expect(stop.1 == (stop.0 == .none ? nil : ring.id.uuidString))
        let secondary = describe(request.secondaryIntent)
        #expect(secondary.0 == spec.action(for: .secondary))
        #expect(secondary.1 == (secondary.0 == .none ? nil : ring.id.uuidString))
    }

    @Test func shell03_buttonsPerKind() {
        #expect(describe(AlarmRequest.make(for: ring(.main), silent: false).stopIntent).0 == .none)
        #expect(describe(AlarmRequest.make(for: ring(.main), silent: false).secondaryIntent).0 == .openToChallenge)
        #expect(describe(AlarmRequest.make(for: ring(.deadline), silent: false).stopIntent).0 == .openToChallenge)
        #expect(describe(AlarmRequest.make(for: ring(.guardRing), silent: false).secondaryIntent).0 == .openToChallenge)
        #expect(describe(AlarmRequest.make(for: ring(.awakeCheck), silent: false).stopIntent).0 == .confirmAwake)
        #expect(describe(AlarmRequest.make(for: ring(.awakeCheck), silent: false).secondaryIntent).0 == .confirmAwake)
        #expect(AlarmRequest.make(for: ring(.nudge), silent: false).secondaryIntent == nil)
        #expect(AlarmRequest.make(for: ring(.nudge), silent: false).stopIntent == nil)
    }

    @Test(arguments: RingKind.allCases)
    func shell04_metadataCarriesWholeRing(kind: RingKind) {
        let ring = ring(kind)
        #expect(AlarmRequest.make(for: ring, silent: false).metadata.ring == ring)
    }

    /// Test runs ring with the bundled silent file (named with its extension, or AlarmKit plays the system
    /// sound); production keeps the system alarm sound.
    @Test(arguments: RingKind.allCases)
    func silentRunsUseTheSilentFile(kind: RingKind) throws {
        #expect(AlarmRequest.make(for: ring(kind), silent: true).soundFile == "silence.caf")
        #expect(AlarmRequest.make(for: ring(kind), silent: false).soundFile == nil)
        let url = try #require(Bundle.main.url(forResource: "silence", withExtension: "caf"))
        #expect(url.lastPathComponent == AlarmRequest.silentSoundFile)
    }

    @Test func shell04_ledgerRebuildsRingsAfterRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var ledger = RingLedger(url: url)
        let main = ring(.main)
        let guardRing = ring(.guardRing)
        ledger.record(main)
        ledger.record(guardRing)

        var reloaded = RingLedger(url: url)
        let alarm = reloaded.systemAlarm(id: main.id, fireDate: main.date, alerting: true)
        #expect(alarm.ring == main)
        #expect(alarm.alerting)
        #expect(reloaded.systemAlarm(id: UUID(), fireDate: nil, alerting: false).ring == nil)

        reloaded.prune(keeping: [main.id])
        #expect(RingLedger(url: url).rings.keys.sorted() == [main.id])
    }
}
