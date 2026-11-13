import ARKit
import CoreMotion
import SwiftUI
import WakelatchCore

// MARK: Eyes open (TrueDepth face tracking)

struct EyesOpenChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var tracker: EyesOpenTracker
    @State private var faceVisible = false

    init(level: Int, onDone: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
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
                        tracker.update(time: time, leftBlink: left, rightBlink: right)
                        if tracker.isDone { onDone() }
                    case .lost:
                        faceVisible = false
                        tracker.faceLost()
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
    }
}

// MARK: Steps

struct StepsChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var steps = 0
    @State private var pedometer = CMPedometer()
    @State private var failed = false

    var body: some View {
        let goal = ChallengeKind.steps.goal(level: level)
        CounterChallengeView(title: "Walk", detail: failed
                             ? "Motion access is off. Turn it on in Settings > Wakelatch, or use the emergency skip."
                             : "Get out of bed and walk around with the phone.",
                             count: steps, goal: goal, unit: "steps")
            .accessibilityIdentifier("challenge.steps")
            .onAppear {
                pedometer.startUpdates(from: .now) { data, error in
                    let count = data?.numberOfSteps.intValue
                    Task { @MainActor in
                        if error != nil { failed = true }
                        if let count {
                            steps = count
                            if count >= goal { onDone() }
                        }
                    }
                }
            }
            .onDisappear { pedometer.stopUpdates() }
    }
}

// MARK: Shake

struct ShakeChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var counter: ShakeCounter
    @State private var motion = CMMotionManager()

    init(level: Int, onDone: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
        _counter = State(initialValue: ShakeCounter(goal: ChallengeKind.shake.goal(level: level)))
    }

    var body: some View {
        CounterChallengeView(title: "Shake", detail: "Shake the phone hard, then let it settle. Hold on tight.",
                             count: counter.count, goal: counter.goal, unit: "shakes")
            .accessibilityIdentifier("challenge.shake")
            .sensoryFeedback(.impact(weight: .light), trigger: counter.count)
            .onAppear {
                motion.accelerometerUpdateInterval = 1.0 / 50
                motion.startAccelerometerUpdates(to: .main) { data, _ in
                    guard let a = data?.acceleration else { return }
                    let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                    MainActor.assumeIsolated {
                        counter.add(magnitude: magnitude)
                        if counter.isDone { onDone() }
                    }
                }
            }
            .onDisappear { motion.stopAccelerometerUpdates() }
    }
}
