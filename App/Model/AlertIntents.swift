import AppIntents
import Foundation
import WakelatchCore

/// Where alert-button intents deliver their action. The app's model by default; tests replace it.
/// Reaching `AppModel.shared` builds the model from the saved state if the intent started the process,
/// so the action is persisted (a pending route) before the intent returns, whatever runs next.
@MainActor
enum IntentInbox {
    static var deliver: (UUID, AlertAction) async -> Void = { id, action in
        await AppModel.shared.receiveAlertAction(id, action)
    }
}

/// "I'm up" on main and snooze alerts, and both buttons on Deadline and guard alerts. Opens Wakelatch
/// straight onto the challenge for the latest due ring (contract B3).
struct OpenToChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open the challenge"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(ringID: UUID) {
        alarmID = ringID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await IntentInbox.deliver(id, .openToChallenge) }
        return .result()
    }
}

/// Both buttons on a "Still up?" alert. Confirms the awake check without opening the app (contract B4).
struct ConfirmAwakeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Confirm you're up"
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(ringID: UUID) {
        alarmID = ringID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await IntentInbox.deliver(id, .confirmAwake) }
        return .result()
    }
}

/// The intent alarms from builds before the morning engine carry. Kept so their buttons still open the app
/// until the first reconcile replaces those alarms; it now asks for the challenge like `OpenToChallengeIntent`.
struct OpenWakelatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Wakelatch"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await IntentInbox.deliver(id, .openToChallenge) }
        return .result()
    }
}
