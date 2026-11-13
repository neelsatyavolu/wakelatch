import SwiftUI
import WakelatchCore

/// Runs the chosen challenge for a ring, with the emergency skip underneath.
struct ChallengeHostView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let ring: ScheduledRing
    @State private var showSkip = false

    private var kind: ChallengeKind {
        let chosen = model.settings.challenge(for: ring)
        return Capabilities.supports(chosen) ? chosen : .math
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RingDial(ring: ring)
                    .frame(width: typeSize.isAccessibilitySize ? 96 : 140)
                    .padding(.top, 8)
                Text(ringLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.graphite)
                    .multilineTextAlignment(.center)
                challenge
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        // Top corner: always visible, far from the keypad.
        .overlay(alignment: .topTrailing) {
            Button("Skip (\(model.skipsLeft))") { showSkip = true }
                .font(.footnote)
                .foregroundStyle(Theme.graphite)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.trailing, 12)
                .accessibilityLabel("Emergency skip, \(model.skipsLeft) left this month")
                .accessibilityIdentifier("challenge.skip")
        }
        .sheet(isPresented: $showSkip) { SkipSheet(ring: ring) }
    }

    private var ringLine: String {
        let p = model.position(of: ring)
        return "Ring \(p.number) of \(p.total)" + (p.deadline.map { ". Deadline \($0.shortTime)." } ?? ".")
    }

    @ViewBuilder private var challenge: some View {
        let done = { model.solved(ring) }
        switch kind {
        case .math: MathChallengeView(level: ring.level, onDone: done)
        case .phrase: PhraseChallengeView(level: ring.level, onDone: done)
        case .eyesOpen: EyesOpenChallengeView(level: ring.level, onDone: done)
        case .steps: StepsChallengeView(level: ring.level, onDone: done)
        case .shake: ShakeChallengeView(level: ring.level, onDone: done)
        }
    }
}

/// Answer field + slab, shared by the typed challenges.
private struct AnswerField: View {
    let prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .numberPad
    var axis: Axis = .horizontal
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.graphite), axis: axis)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(keyboard == .numberPad ? .title.monospacedDigit() : .title3)
            .multilineTextAlignment(keyboard == .numberPad ? .center : .leading)
            .padding(14)
            .background(Theme.face.opacity(0.08), in: .rect(cornerRadius: Theme.radius))
            .focused($focused)
            .onAppear { focused = true }
            .accessibilityIdentifier("challenge.answer")
    }
}

struct MathChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var problem: MathChallenge
    @State private var solvedCount = 0
    @State private var answer = ""
    @State private var wrong = false

    init(level: Int, onDone: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
        var rng = SystemRandomNumberGenerator()
        _problem = State(initialValue: MathChallenge.make(level: level, using: &rng))
    }

    private var goal: Int { ChallengeKind.math.goal(level: level) }

    var body: some View {
        VStack(spacing: 20) {
            Text(goal > 1 ? "Problem \(solvedCount + 1) of \(goal)" : "Solve to stop")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("challenge.headline")
            Text(problem.prompt)
                .font(.system(.largeTitle).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel("What is \(problem.prompt)?")
                .accessibilityIdentifier("challenge.problem")
            AnswerField(prompt: "Answer", text: $answer)
            Text(wrong ? "Not it. New problem." : " ")
                .foregroundStyle(Theme.graphite)
                .accessibilityHidden(!wrong)
            Button("Submit answer", action: submit)
                .buttonStyle(.slab)
                .disabled(answer.isEmpty)
                .accessibilityIdentifier("challenge.submit")
        }
        .sensoryFeedback(.error, trigger: wrong) { _, new in new }
        // Check as soon as the answer has as many digits as the right one; no reaching for Submit.
        .onChange(of: answer) { _, typed in
            if typed.count >= String(problem.answer).count { submit() }
        }
    }

    private func submit() {
        var rng = SystemRandomNumberGenerator()
        // Later problems in a set use multiplication.
        let nextLevel = solvedCount + 1 < goal ? level : max(level, 3)
        if problem.check(answer) {
            solvedCount += 1
            wrong = false
            if solvedCount >= goal { onDone(); return }
            problem = MathChallenge.make(level: nextLevel, using: &rng)
        } else {
            wrong = true
            problem = MathChallenge.make(level: level, using: &rng)
        }
        answer = ""
    }
}

struct PhraseChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var challenge: PhraseChallenge
    @State private var text = ""
    @State private var wrong = false

    init(level: Int, onDone: @escaping () -> Void) {
        self.level = level
        self.onDone = onDone
        var rng = SystemRandomNumberGenerator()
        _challenge = State(initialValue: PhraseChallenge.make(level: level, using: &rng))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Type this").font(.title2.weight(.semibold))
            Text(challenge.phrase)
                .font(.title2)
                .accessibilityIdentifier("challenge.phrase")
            AnswerField(prompt: "Type it here", text: $text, keyboard: .default, axis: .vertical)
            if wrong { Text("Not quite. Check each word.").foregroundStyle(Theme.graphite) }
            Button("Submit") {
                if challenge.check(text) { onDone() } else { wrong = true }
            }
            .buttonStyle(.slab)
            .disabled(text.isEmpty)
            .accessibilityIdentifier("challenge.submit")
        }
    }
}

/// Big number with a goal, used by steps and shakes.
struct CounterChallengeView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 96
    let title: String
    let detail: String
    let count: Int
    let goal: Int
    let unit: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            Text("\(min(count, goal))")
                .font(.system(size: min(countSize, 140), weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            Text("of \(goal) \(unit)").font(.title3).foregroundStyle(Theme.graphite)
            ProgressView(value: Double(min(count, goal)), total: Double(goal))
                .tint(Theme.face)
            Text(detail).foregroundStyle(Theme.graphite).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(min(count, goal)) of \(goal) \(unit).")
    }
}
