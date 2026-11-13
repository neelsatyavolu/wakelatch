import SwiftUI
import WakelatchCore

/// Morning screen: one dial, one sentence, one problem.
struct ChallengeView: View {
    @Environment(LatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var problem = ChallengeView.newProblem()
    @State private var answer = ""
    @State private var wrong = false
    @State private var released = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
        VStack(spacing: 28) {
            StationDial(
                rings: store.chainDates.map(\.minuteFraction),
                latched: !released,
                activeRing: store.pendingRing
            )
            .frame(width: typeSize.isAccessibilitySize ? 140 : 220)
            .padding(.top, typeSize.isAccessibilitySize ? 8 : 24)

            Text(headline)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityIdentifier("challenge.headline")

            Text(problem.prompt)
                .font(.system(.largeTitle, design: .default).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel("What is \(problem.prompt)?")
                .accessibilityIdentifier("challenge.problem")

            VStack(spacing: 12) {
                TextField("Answer", text: $answer, prompt: Text("Answer").foregroundStyle(Theme.graphite))
                    .keyboardType(.numberPad)
                    .font(.title.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Theme.face.opacity(0.08), in: .rect(cornerRadius: Theme.radius))
                    .focused($focused)
                    .accessibilityLabel("Answer")
                    .accessibilityIdentifier("challenge.answer")

                Text(wrong ? "Not it. New problem." : " ")
                    .font(.subheadline)
                    .foregroundStyle(Theme.graphite)
                    .accessibilityHidden(!wrong)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .safeAreaInset(edge: .bottom) {
            Button("Submit answer", action: submit)
                .buttonStyle(.slab)
                .accessibilityIdentifier("challenge.submit")
                .disabled(answer.isEmpty || released)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.enamel)
        .foregroundStyle(Theme.face)
        .tint(Theme.face)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: released)
        .sensoryFeedback(.error, trigger: problem)
        .onAppear { focused = true }
    }

    private var headline: String {
        if released { return "Released." }
        let total = store.chainIDs.count
        guard let ring = store.pendingRing, total > 0 else { return "Solve to stop." }
        return "Ring \(ring + 1) of \(total). Solve to stop."
    }

    private static func newProblem() -> MathChallenge {
        var rng = SystemRandomNumberGenerator()
        return MathChallenge.make(level: 2, using: &rng)
    }

    private func submit() {
        guard problem.check(answer) else {
            store.record("wrong answer to \(problem.prompt)")
            wrong = true
            answer = ""
            problem = Self.newProblem()
            return
        }
        store.record("challenge solved; cancelling \(store.chainIDs.count) rings")
        AlarmLab.cancelChain()
        RemovalLock.setLocked(false)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5)) {
            released = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            store.setChallengePending(false)
        }
    }
}
