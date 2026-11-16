import ARKit
import CoreMotion
import SwiftUI
import WakelatchCore

// MARK: Eyes open (TrueDepth face tracking)

struct EyesOpenChallengeView: View {
    @Environment(AppModel.self) private var model
    let level: Int
    let onDone: () -> Void
    /// The camera was refused or failed: the engine switches this challenge to math (C4).
    let onUnavailable: () -> Void
    @State private var tracker: EyesOpenTracker
    @State private var faceVisible = false
    @State private var latch = OnceLatch()

    init(level: Int, onDone: @escaping () -> Void, onUnavailable: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
        self.onUnavailable = onUnavailable
        _tracker = State(initialValue: EyesOpenTracker(goal: Double(ChallengeKind.eyesOpen.goal(level: level))))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Keep your eyes open").font(.title2.weight(.semibold))
            ZStack {
                FaceCameraView { sample in
                    switch sample {
                    case let .face(time, left, right):
                        faceVisible = true
                        model.challengeActivity()
                        tracker.update(time: time, leftBlink: left, rightBlink: right)
                        if tracker.isDone { latch.fire(onDone) }
                    case .lost:
                        faceVisible = false
                        tracker.faceLost()
                    case .failed:
                        latch.fire(onUnavailable)
                    }
                }
                .clipShape(.circle)
                Circle()
                    .trim(from: 0, to: tracker.progress)
                    .stroke(Theme.face, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: tracker.progress)
            }
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)
            Text(faceVisible ? "\(Int((tracker.goal - tracker.openSeconds).rounded(.up))) seconds left."
                             : "Hold the phone in front of your face.")
                .font(.title3.monospacedDigit())
                .accessibilityIdentifier("challenge.eyes")
            Text("Normal blinks are fine. Close your eyes for two seconds and it starts over.")
                .foregroundStyle(Theme.graphite)
                .multilineTextAlignment(.center)
        }
    }
}

enum FaceSample: Sendable {
    case face(time: Double, left: Double, right: Double)
    case lost
    /// The session failed, for example because camera access was refused.
    case failed
}

/// Front camera preview that reports eye blink weights.
struct FaceCameraView: UIViewRepresentable {
    let onSample: @MainActor (FaceSample) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSample: onSample) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = false
        view.session.delegate = context.coordinator
        view.session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate, @unchecked Sendable {
        let onSample: @MainActor (FaceSample) -> Void

        init(onSample: @escaping @MainActor (FaceSample) -> Void) {
            self.onSample = onSample
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let sample: FaceSample = face.isTracked
                ? .face(time: ProcessInfo.processInfo.systemUptime,
                        left: face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0,
                        right: face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0)
                : .lost
            let send = onSample
            Task { @MainActor in send(sample) }
        }

        nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            let send = onSample
            Task { @MainActor in send(.lost) }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
            let send = onSample
            Task { @MainActor in send(.failed) }
        }
    }
}

// MARK: Steps

struct StepsChallengeView: View {
    @Environment(AppModel.self) private var model
    let level: Int
    let onDone: () -> Void
    /// Motion access was refused or the pedometer failed: the engine switches this challenge to math (C4).
    let onUnavailable: () -> Void
    @State private var steps = 0
    @State private var pedometer = CMPedometer()
    @State private var latch = OnceLatch()

    var body: some View {
        let goal = ChallengeKind.steps.goal(level: level)
        CounterChallengeView(title: "Walk", detail: "Get out of bed and walk around with the phone.",
                             count: steps, goal: goal, unit: "steps")
            .accessibilityIdentifier("challenge.steps")
            .onAppear {
                pedometer.startUpdates(from: .now) { data, error in
                    let count = data?.numberOfSteps.intValue
                    let failed = error != nil
                    Task { @MainActor in update(count: count, failed: failed, goal: goal) }
                }
            }
            .onDisappear { pedometer.stopUpdates() }
    }

    private func update(count: Int?, failed: Bool, goal: Int) {
        if failed {
            pedometer.stopUpdates()
            latch.fire(onUnavailable)
            return
        }
        guard let count else { return }
        if count > steps { model.challengeActivity() }
        steps = count
        if count >= goal {
            pedometer.stopUpdates()
            latch.fire(onDone)
        }
    }
}

// MARK: Shake

struct ShakeChallengeView: View {
    @Environment(AppModel.self) private var model
    let level: Int
    let onDone: () -> Void
    /// No accelerometer: the engine switches this challenge to math (C4).
    let onUnavailable: () -> Void
    @State private var counter: ShakeCounter
    @State private var motion = CMMotionManager()
    @State private var latch = OnceLatch()

    init(level: Int, onDone: @escaping () -> Void, onUnavailable: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
        self.onUnavailable = onUnavailable
        _counter = State(initialValue: ShakeCounter(goal: ChallengeKind.shake.goal(level: level)))
    }

    var body: some View {
        CounterChallengeView(title: "Shake", detail: "Shake the phone hard, then let it settle. Hold on tight.",
                             count: counter.count, goal: counter.goal, unit: "shakes")
            .accessibilityIdentifier("challenge.shake")
            .sensoryFeedback(.impact(weight: .light), trigger: counter.count)
            .onChange(of: counter.count) { model.challengeActivity() }
            .onAppear {
                guard motion.isAccelerometerAvailable else { return latch.fire(onUnavailable) }
                motion.accelerometerUpdateInterval = 1.0 / 50
                motion.startAccelerometerUpdates(to: .main) { data, _ in
                    guard let a = data?.acceleration else { return }
                    let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                    MainActor.assumeIsolated {
                        counter.add(magnitude: magnitude)
                        guard counter.isDone else { return }
                        motion.stopAccelerometerUpdates()
                        latch.fire(onDone)
                    }
                }
            }
            .onDisappear { motion.stopAccelerometerUpdates() }
    }
}

/// Lets a sensor challenge report its result once, however many samples arrive after it (fix 15).
@MainActor
final class OnceLatch {
    private(set) var fired = false

    func fire(_ action: () -> Void) {
        guard !fired else { return }
        fired = true
        action()
    }
}
