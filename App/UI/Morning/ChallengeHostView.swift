import SwiftUI
import WakelatchCore

/// Runs the chosen challenge for a ring, with the emergency skip underneath.
struct ChallengeHostView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The engine's challenge: the ring's snapshotted kind at its level (C1, C3).
    let challenge: ActiveChallenge
    @State private var showSkip = false
    /// Checked once per challenge (the view is keyed by it): the sensor exists and its permission was given.
    @State private var runnable: Bool

    init(challenge: ActiveChallenge) {
        self.challenge = challenge
        _runnable = State(initialValue: Capabilities.canRunNow(challenge.kind))
    }

    private var ring: Ring { challenge.ring }

    /// The engine's kind. One this phone can't run now (no sensor, or permission not given) is shown as
    /// math, and the engine is told so it switches the challenge to math as well (C4).
    private var kind: ChallengeKind { runnable ? challenge.kind : .math }

    /// The sensor failed or permission was refused while the challenge ran.
    private func unavailable() { model.challengeUnavailable(challenge.kind) }

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
                challengeView
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
        .onAppear {
            if kind != challenge.kind { unavailable() }
        }
    }

    private var ringLine: String {
        let p = model.position(of: ring)
        return "Ring \(p.number) of \(p.total)" + (p.deadline.map { ". Deadline \($0.shortTime)." } ?? ".")
    }

    /// The level is the engine's (the ring's), never a setting read now.
    @ViewBuilder private var challengeView: some View {
        let done = { model.solved(ring) }
        let level = challenge.level
        switch kind {
        case .math: MathChallengeView(level: level, onDone: done)
        case .phrase: PhraseChallengeView(level: level, onDone: done)
        case .eyesOpen: EyesOpenChallengeView(level: level, onDone: done, onUnavailable: unavailable)
        case .steps: StepsChallengeView(level: level, onDone: done, onUnavailable: unavailable)
        case .shake: ShakeChallengeView(level: level, onDone: done, onUnavailable: unavailable)
        }
    }
}

/// Answer field + slab, shared by the typed challenges.
private struct AnswerField: View {
    @Environment(AppModel.self) private var model
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
            // Typing keeps the challenge in use, so it silences the rings that come while it is open (F4).
            .onChange(of: text) { model.challengeActivity() }
            .accessibilityIdentifier("challenge.answer")
    }
}

/// Math from the core `MathSession`: it checks once the answer is long enough, and every wrong answer
/// gives a new problem and feedback (M2-M5). `onDone` runs once, on `.done`.
struct MathChallengeView: View {
    let onDone: () -> Void
    @State private var session: MathSession
    /// The step the last check gave, for the feedback line.
    @State private var last: MathSession.Step = .pending
    /// What the field shows. Kept apart from the session and cleared after each check from `onChange`:
    /// clearing it from inside the field's own binding setter sometimes left the typed digits on screen,
    /// and they were joined to the next answer (U14).
    @State private var text = ""

    init(level: Int, onDone: @escaping () -> Void) {
        self.onDone = onDone
        var rng = SystemRandomNumberGenerator()
        _session = State(initialValue: MathSession(level: level, using: &rng))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(session.headline)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("challenge.headline")
            Text(session.problem.prompt)
                .font(.system(.largeTitle).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel("What is \(session.problem.prompt)?")
                .accessibilityIdentifier("challenge.problem")
            AnswerField(prompt: "Answer", text: $text)
                .onChange(of: text) { _, typed in enter(typed) }
            Text(last == .wrong ? missLine : " ")
                .foregroundStyle(Theme.graphite)
                .accessibilityHidden(last != .wrong)
                .accessibilityIdentifier("challenge.feedback")
            Button("Submit answer") {
                take { session.submit(using: &$0) }
                text = session.answer
            }
                .buttonStyle(.slab)
                .disabled(session.answer.isEmpty || session.isDone)
                .accessibilityIdentifier("challenge.submit")
        }
        // Every miss, not only the first (fix 19).
        .sensoryFeedback(.error, trigger: session.misses)
    }

    /// Changes with every miss, so a second wrong answer reads differently from the first (fix 19).
    private var missLine: String {
        session.misses > 1 ? "Not it again (\(session.misses) wrong). New problem." : "Not it. New problem."
    }

    /// Typing goes into the session, which checks it once it has as many digits as the answer. A check
    /// empties the session's answer, and the field follows.
    private func enter(_ typed: String) {
        guard typed != session.answer else { return }
        take { session.enter(typed, using: &$0) }
        if text != session.answer { text = session.answer }
    }

    private func take(_ step: (inout SystemRandomNumberGenerator) -> MathSession.Step) {
        var rng = SystemRandomNumberGenerator()
        let result = step(&rng)
        switch result {
        case .pending, .ignored: return
        case .wrong, .correct: last = result
        case .done:
            last = result
            onDone()
        }
    }
}

struct PhraseChallengeView: View {
    let level: Int
    let onDone: () -> Void
    @State private var challenge: PhraseChallenge
    @State private var text = ""
    @State private var wrong = false
    @State private var latch = OnceLatch()

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
                if challenge.check(text) { latch.fire(onDone) } else { wrong = true }
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
