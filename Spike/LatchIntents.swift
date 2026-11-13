@preconcurrency import AlarmKit
import AppIntents

struct SpikeAlarmMetadata: AlarmMetadata {
    var role: String
}

/// Attached to every ring as both the stop intent and the "Solve" secondary
/// button. Spike question (b): does tapping Stop bring the app forward
/// straight into the challenge?
struct OpenChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open challenge"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "Source")
    var source: String

    init() {}

    init(alarmID: UUID, source: String) {
        self.alarmID = alarmID.uuidString
        self.source = source
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = LatchStore.shared
        store.record("\(source) intent ran for \(alarmID.prefix(8))")
        if let ring = store.chainIDs.firstIndex(where: { $0.uuidString == alarmID }) {
            store.setChallengePending(true, ring: ring)
        }
        return .result()
    }
}
