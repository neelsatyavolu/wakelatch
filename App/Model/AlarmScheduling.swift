@preconcurrency import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import WakelatchCore

/// Everything AppModel asks of AlarmKit. `AlarmDriver` is the real one; tests use a fake.
protocol AlarmScheduling: Sendable {
    /// Hands the ring to AlarmKit with the alert from `AlertSpec.for(ring.kind)`. Replaces an alarm with the same id.
    func schedule(_ ring: Ring) async throws
    /// Stops the alarm if it is alerting and removes it.
    func cancel(_ id: UUID) async
    /// Silences an alerting alarm. Later rings stay scheduled.
    func stop(_ id: UUID) async
    /// AlarmKit's current table, with each alarm's ring when Wakelatch scheduled it.
    func table() async -> [SystemAlarm]
    /// The table again each time AlarmKit reports a change (an alarm starts or stops alerting, or is added).
    func alarmUpdates() -> AsyncStream<[SystemAlarm]>
}

/// Travels with every alarm. The whole ring is here (id, morning, kind, level, date, group, challenge).
struct WakelatchAlarmMetadata: AlarmMetadata {
    let ring: Ring
}

/// The system alert for one ring, before it becomes an AlarmKit configuration. Kept as plain values so a
/// test can check every kind's buttons and intents against `AlertSpec`.
struct AlarmRequest {
    let ring: Ring
    let title: String
    /// Nil when the alert has only Stop.
    let secondaryLabel: String?
    let secondarySymbol: String?
    /// The intent Stop runs, or nil when Stop only stops this ring (the system snooze before the Deadline).
    let stopIntent: (any LiveActivityIntent)?
    let secondaryIntent: (any LiveActivityIntent)?
    let metadata: WakelatchAlarmMetadata
    /// The bundled sound file the alarm rings with, or nil for the system alarm sound.
    let soundFile: String?

    /// A bundled file of silence. AlarmKit needs the name with its extension, or it falls back to the
    /// system sound.
    static let silentSoundFile = "silence.caf"

    /// - Parameter silent: UI tests only (`LaunchOptions.silent`): ring with `silentSoundFile`.
    static func make(for ring: Ring, silent: Bool) -> AlarmRequest {
        let spec = AlertSpec.for(ring.kind)
        let secondary = spec.secondaryLabel == nil ? nil : intent(for: spec.secondary, ringID: ring.id)
        return AlarmRequest(ring: ring, title: spec.title, secondaryLabel: spec.secondaryLabel,
                            secondarySymbol: spec.secondarySymbol,
                            stopIntent: intent(for: spec.stop, ringID: ring.id), secondaryIntent: secondary,
                            metadata: WakelatchAlarmMetadata(ring: ring),
                            soundFile: silent ? silentSoundFile : nil)
    }

    /// The intent behind an alert action: open to the challenge (foreground), confirm awake (background).
    static func intent(for action: AlertAction, ringID: UUID) -> (any LiveActivityIntent)? {
        switch action {
        case .none: nil
        case .openToChallenge: OpenToChallengeIntent(ringID: ringID)
        case .confirmAwake: ConfirmAwakeIntent(ringID: ringID)
        }
    }

    var configuration: AlarmManager.AlarmConfiguration<WakelatchAlarmMetadata> {
        let alert: AlarmPresentation.Alert
        if let secondaryLabel {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: AlarmButton(text: LocalizedStringResource(stringLiteral: secondaryLabel),
                                             textColor: .black, systemImageName: secondarySymbol ?? "sun.horizon"),
                secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title))
        }
        let attributes = AlarmAttributes<WakelatchAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert), metadata: metadata, tintColor: Theme.face)
        return .alarm(
            schedule: .fixed(ring.date),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent,
            // Production uses the system sound: a custom sound once crashed iOS's tone player (SpringBoard
            // abort in TLAlertQueuePlayerController, seen in the iOS 26.5 simulator), which swallows the alarm.
            // The in-app alarm plays Wakelatch's own chime. Only UI tests use the silent file.
            sound: soundFile.map { .named($0) } ?? .default)
    }
}
