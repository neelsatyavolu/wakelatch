@preconcurrency import AlarmKit
import AppIntents
import Foundation
import SwiftUI

struct WakelatchAlarmMetadata: AlarmMetadata {
    var kind: String
}

/// Brings Wakelatch forward from the alarm. The app decides what to show from
/// its own schedule when it becomes active, so this intent only needs to open it.
struct OpenWakelatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Wakelatch"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult { .result() }
}

/// The only place that talks to AlarmKit.
@MainActor
enum AlarmService {
    private static var manager: AlarmManager { .shared }

    static var isAuthorized: Bool { manager.authorizationState == .authorized }
    static var isDenied: Bool { manager.authorizationState == .denied }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        if isAuthorized { return true }
        return (try? await manager.requestAuthorization()) == .authorized
    }

    static func schedule(_ ring: ScheduledRing) async throws {
        _ = try await manager.schedule(id: ring.id, configuration: configuration(for: ring))
    }

    static func cancel(_ id: UUID) {
        try? manager.stop(id: id)
        try? manager.cancel(id: id)
    }

    /// Silences a ringing alarm (the in-app screen takes over).
    static func silence(_ id: UUID) {
        try? manager.stop(id: id)
    }

    static func cancelAll() {
        for alarm in (try? manager.alarms) ?? [] { cancel(alarm.id) }
    }

    static func systemAlarmIDs() -> Set<UUID> {
        Set(((try? manager.alarms) ?? []).map(\.id))
    }

    static func watchAuthorization(_ onChange: @escaping @MainActor () -> Void) async {
        for await _ in manager.authorizationUpdates { onChange() }
    }

    /// Calls `onRinging` with the IDs of alarms that are sounding right now.
    static func watch(onRinging: @escaping @MainActor (Set<UUID>) -> Void) async {
        for await alarms in manager.alarmUpdates {
            onRinging(Set(alarms.filter { $0.state == .alerting }.map(\.id)))
        }
    }

    private static func configuration(for ring: ScheduledRing) -> AlarmManager.AlarmConfiguration<WakelatchAlarmMetadata> {
        let open = OpenWakelatchIntent(alarmID: ring.id)
        let alert: AlarmPresentation.Alert
        var stopIntent: OpenWakelatchIntent?
        switch ring.kind {
        case .nudge:
            alert = AlarmPresentation.Alert(title: "Wakelatch. Ideal time soon.")
        case .main, .snooze:
            alert = AlarmPresentation.Alert(
                title: "Wakelatch. Stop to snooze.",
                secondaryButton: AlarmButton(text: "I'm up", textColor: .black, systemImageName: "sun.horizon"),
                secondaryButtonBehavior: .custom)
        case .deadline, .guardRing:
            alert = AlarmPresentation.Alert(
                title: "Wakelatch. Deadline. Solve to stop.",
                secondaryButton: AlarmButton(text: "Solve", textColor: .black, systemImageName: "lock.open"),
                secondaryButtonBehavior: .custom)
            stopIntent = open
        case .awakeCheck:
            alert = AlarmPresentation.Alert(
                title: "Wakelatch. Still up?",
                secondaryButton: AlarmButton(text: "I'm up", textColor: .black, systemImageName: "checkmark"),
                secondaryButtonBehavior: .custom)
            stopIntent = open
        }
        let attributes = AlarmAttributes<WakelatchAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakelatchAlarmMetadata(kind: ring.kind.rawValue),
            tintColor: Theme.face)
        return .alarm(
            schedule: .fixed(ring.date),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: ring.kind == .nudge ? nil : open,
            // A custom sound crashed iOS's tone player (SpringBoard abort in TLAlertQueuePlayerController,
            // seen in the iOS 26.5 simulator), which swallows the alarm. The system sound is the safe choice;
            // the in-app alarm plays Wakelatch's own chime.
            sound: .default)
    }
}
