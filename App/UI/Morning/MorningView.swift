import SwiftUI
import UIKit
import WakelatchCore

/// Hosts the morning screens and the in-app alarm sound.
struct MorningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.screen {
            case .none: Color.black
            case let .ringing(ring, _): RingingView(ring: ring)
            case let .challenge(ring): ChallengeHostView(ring: ring)
            case let .awakeCheck(ring): AwakeCheckView(ring: ring)
            case let .released(record): ReleasedView(record: record)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.enamel)
        .foregroundStyle(Theme.face)
        .tint(Theme.face)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .onChange(of: model.screen, initial: true) { _, screen in updateSound(screen) }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            RingPlayer.shared.stop()
        }
    }

    private func updateSound(_ screen: MorningScreen) {
        switch screen {
        case let .ringing(ring, sounding):
            if sounding { RingPlayer.shared.play(nudge: ring.kind == .nudge) }
            RingPlayer.shared.duck(false)
        case .challenge:
            RingPlayer.shared.duck(true)
        case let .awakeCheck(ring):
            if Date.now.timeIntervalSince(ring.date) < 90 { RingPlayer.shared.play(nudge: false) }
        case .released, .none:
            RingPlayer.shared.stop()
        }
    }
}

/// The ring itself: the time, the dial with the disc parked at twelve, and what Stop means now.
struct RingingView: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 72
    let ring: ScheduledRing

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 24) {
                RingDial(ring: ring)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .padding(.top, 16)
                Text((model.demoNow ?? context.date).shortTime)
                    .font(.system(size: min(clockSize, 110), weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityIdentifier("ringing.time")
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ringing.headline")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                switch ring.kind {
                case .nudge:
                    Button("Stop") { model.dismissNudge(ring) }
                        .buttonStyle(.slab)
                        .accessibilityIdentifier("ringing.stop")
                case .main, .snooze:
                    Button("Start challenge") { model.startChallenge(ring) }
                        .buttonStyle(.slab)
                        .accessibilityIdentifier("ringing.up")
                    Button(snoozeTitle) { model.snooze(ring) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("ringing.snooze")
                default:
                    Button("Solve to stop") { model.startChallenge(ring) }
                        .buttonStyle(.slab)
                        .accessibilityIdentifier("ringing.solve")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var headline: String {
        let p = model.position(of: ring)
        switch ring.kind {
        case .nudge:
            return "Ideal at \(ring.morning.shortTime). This one stops with a tap."
        case .main, .snooze:
            let deadline = p.deadline.map { " Deadline \($0.shortTime)." } ?? ""
            return "Ring \(p.number) of \(p.total).\(deadline)"
        default:
            return "Ring \(p.number) of \(p.total). Past the deadline, only the challenge stops it."
        }
    }

    private var snoozeTitle: String {
        let next = model.latchedRings(of: ring.morning).first { $0.date > ring.date }
        return next.map { "Snooze until \($0.date.shortTime)" } ?? "Snooze"
    }
}

/// The morning's rings on the dial, the sounding one in red, disc parked at twelve.
struct RingDial: View {
    @Environment(AppModel.self) private var model
    let ring: ScheduledRing

    var body: some View {
        let latched = model.latchedRings(of: ring.morning)
        MorningDial(dates: latched.map(\.date), latched: ring.latched,
                    activeIndex: latched.firstIndex { $0.id == ring.id })
    }
}

/// "Still up?" a few minutes after the challenge.
struct AwakeCheckView: View {
    @Environment(AppModel.self) private var model
    let ring: ScheduledRing

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            StationDial(rings: [], latched: false).frame(maxWidth: 180)
            Text("Still up?").font(.largeTitle.weight(.bold))
            Text("One tap and this check is done.").foregroundStyle(Theme.graphite)
            Spacer()
        }
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            Button("I'm up") { model.confirmAwake(ring) }
                .buttonStyle(.slab)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .accessibilityIdentifier("awake.up")
        }
    }
}

/// After the challenge: the disc swings away and the morning's facts are shown.
struct ReleasedView: View {
    @Environment(AppModel.self) private var model
    let record: MorningRecord
    @State private var released = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            StationDial(rings: [], latched: !released).frame(maxWidth: 200)
            Text("Released.").font(.largeTitle.weight(.bold)).accessibilityIdentifier("released.title")
            VStack(spacing: 6) {
                if let up = record.upAt { Text("Up at \(up.shortTime). Ideal was \(record.ideal.shortTime).") }
                if model.settings.awakeChecks {
                    let checks = model.pendingAwakeChecks.map(\.shortTime)
                    Text(checks.isEmpty ? "Awake checks in 5 and 12 minutes."
                                        : "Awake checks at \(checks.joined(separator: " and ")).")
                        .foregroundStyle(Theme.graphite)
                }
            }
            .font(.title3)
            .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            Button("Done") { model.closeReleased() }
                .buttonStyle(.slab)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .accessibilityIdentifier("released.done")
        }
        .sensoryFeedback(.success, trigger: released)
        .onAppear {
            withAnimation(.spring(duration: 0.5).delay(0.2)) { released = true }
        }
    }
}
