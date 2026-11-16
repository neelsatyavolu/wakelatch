import ARKit
import AVFoundation
import CoreMotion
import WakelatchCore

/// Where a sensor's permission stands. Kinds that need no permission are always `.granted`.
enum SensorAccess: Equatable, Sendable {
    case granted
    /// iOS has not asked yet. It asks when the kind is chosen, or at the latest when the sensor starts.
    case notAsked
    /// Denied or restricted. The challenge can't run, so the engine falls back to math (C4).
    case denied

    init(camera status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }

    init(motion status: CMAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }
}

/// Which challenges this phone can run: the hardware is there and the permission is not denied.
enum Capabilities {
    /// The rule on its own, so tests can check it without real sensors.
    static func usable(hardware: Bool, access: SensorAccess) -> Bool {
        hardware && access != .denied
    }

    static func supports(_ kind: ChallengeKind) -> Bool {
        usable(hardware: hasHardware(kind), access: access(kind))
    }

    /// The rule at alarm time: a sensor challenge runs only when its permission was already given (the picker
    /// asks when the kind is chosen), so no permission prompt ever appears during an alarm. Anything else
    /// falls back to math for that challenge (C4).
    static func ready(hardware: Bool, access: SensorAccess) -> Bool {
        hardware && access == .granted
    }

    static func canRunNow(_ kind: ChallengeKind) -> Bool {
        ready(hardware: hasHardware(kind), access: access(kind))
    }

    static func hasHardware(_ kind: ChallengeKind) -> Bool {
        switch kind {
        case .math, .phrase: true
        case .eyesOpen: ARFaceTrackingConfiguration.isSupported
        case .steps: CMPedometer.isStepCountingAvailable()
        case .shake: CMMotionManager().isAccelerometerAvailable
        }
    }

    static func access(_ kind: ChallengeKind) -> SensorAccess {
        switch kind {
        case .eyesOpen: SensorAccess(camera: AVCaptureDevice.authorizationStatus(for: .video))
        case .steps: SensorAccess(motion: CMPedometer.authorizationStatus())
        case .math, .phrase, .shake: .granted
        }
    }

    /// Asks for the sensor's permission if iOS has not asked yet. Returns whether the kind can run.
    static func requestAccess(_ kind: ChallengeKind) async -> Bool {
        guard hasHardware(kind) else { return false }
        guard access(kind) == .notAsked else { return supports(kind) }
        switch kind {
        case .eyesOpen: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .steps: await askForMotion()
        case .math, .phrase, .shake: break
        }
        return supports(kind)
    }

    static func unavailableReason(_ kind: ChallengeKind) -> String {
        if hasHardware(kind) {
            return switch kind {
            case .eyesOpen: "Camera access is off. Turn it on in Settings > Wakelatch."
            case .steps: "Motion access is off. Turn it on in Settings > Wakelatch."
            case .math, .phrase, .shake: ""
            }
        }
        return switch kind {
        case .eyesOpen: "Needs a Face ID camera."
        case .steps: "Needs step counting."
        case .shake: "Needs motion sensors."
        case .math, .phrase: ""
        }
    }

    /// CoreMotion has no request call: the first pedometer query shows the prompt.
    private static func askForMotion() async {
        let pedometer = CMPedometer()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: .now.addingTimeInterval(-60), to: .now) { _, _ in
                done.resume()
            }
        }
        withExtendedLifetime(pedometer) {}
    }
}
