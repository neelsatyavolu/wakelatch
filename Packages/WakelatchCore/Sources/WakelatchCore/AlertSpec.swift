import Foundation

/// What pressing a system alert button asks the app to do. `.none` means the system handles it alone:
/// the ring stops and the next scheduled ring still comes.
public enum AlertAction: String, Codable, Hashable, Sendable {
    case none
    /// Open Wakelatch (foreground intent) on the challenge of the latest due ring.
    case openToChallenge
    /// Confirm an awake check in the background (no foreground needed).
    case confirmAwake
}

/// The two buttons of a system alarm alert.
public enum AlertButton: String, Hashable, Sendable, CaseIterable {
    case stop, secondary
}

/// The system alert for a ring kind: title, secondary button, and what each button does.
public struct AlertSpec: Hashable, Sendable {
    public let title: String
    /// Nil when the alert has only Stop.
    public let secondaryLabel: String?
    public let secondarySymbol: String?
    public let stop: AlertAction
    public let secondary: AlertAction

    public init(title: String, secondaryLabel: String?, secondarySymbol: String?,
                stop: AlertAction, secondary: AlertAction) {
        self.title = title
        self.secondaryLabel = secondaryLabel
        self.secondarySymbol = secondarySymbol
        self.stop = stop
        self.secondary = secondary
    }

    public static func `for`(_ kind: RingKind) -> AlertSpec {
        switch kind {
        case .nudge:
            AlertSpec(title: "Wakelatch. Ideal time soon.", secondaryLabel: nil, secondarySymbol: nil,
                      stop: .none, secondary: .none)
        case .main, .snooze:
            AlertSpec(title: "Wakelatch. Stop to snooze.", secondaryLabel: "I'm up", secondarySymbol: "sun.horizon",
                      stop: .none, secondary: .openToChallenge)
        case .deadline, .guardRing:
            AlertSpec(title: "Wakelatch. Deadline. Solve to stop.", secondaryLabel: "Solve", secondarySymbol: "lock.open",
                      stop: .openToChallenge, secondary: .openToChallenge)
        case .awakeCheck:
            AlertSpec(title: "Wakelatch. Still up?", secondaryLabel: "I'm up", secondarySymbol: "checkmark",
                      stop: .confirmAwake, secondary: .confirmAwake)
        }
    }

    public func action(for button: AlertButton) -> AlertAction {
        switch button {
        case .stop: stop
        case .secondary: secondaryLabel == nil ? .none : secondary
        }
    }
}
