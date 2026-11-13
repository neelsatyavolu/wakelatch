#if WAKELATCH_NO_FAMILY_CONTROLS
/// Builds without Apple's Family Controls distribution approval (TestFlight
/// betas) leave the deletion block out entirely.
@MainActor
enum RemovalLock {
    static let isAvailable = false
    static var isAuthorized: Bool { false }
    static func requestAuthorization() async throws {}
    static var isLocked: Bool { false }
    static func setLocked(_ locked: Bool) {}
}
#else
import FamilyControls
import ManagedSettings

/// Spike question (d): can the app block its own deletion while it rings?
/// Needs the Family Controls entitlement (development use works without
/// Apple's approval) and the user's Screen Time consent.
@MainActor
enum RemovalLock {
    static let isAvailable = true
    private static let store = ManagedSettingsStore()

    static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    static func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    static var isLocked: Bool {
        store.application.denyAppRemoval == true
    }

    static func setLocked(_ locked: Bool) {
        store.application.denyAppRemoval = locked ? true : nil
    }
}
#endif
