import ARKit
import CoreMotion
import WakelatchCore

/// Which challenges this phone can run.
enum Capabilities {
    static func supports(_ kind: ChallengeKind) -> Bool {
        switch kind {
        case .math, .phrase: true
        case .eyesOpen: ARFaceTrackingConfiguration.isSupported
        case .steps: CMPedometer.isStepCountingAvailable()
        case .shake: CMMotionManager().isAccelerometerAvailable
        }
    }

    static func unavailableReason(_ kind: ChallengeKind) -> String {
        switch kind {
        case .eyesOpen: "Needs a Face ID camera."
        case .steps: "Needs step counting."
        case .shake: "Needs motion sensors."
        case .math, .phrase: ""
        }
    }
}
