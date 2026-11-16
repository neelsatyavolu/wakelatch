import SwiftUI
import UIKit
import WakelatchCore

/// Hosts the morning screens. Sound and the idle timer come from the model.
struct MorningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.screen {
            case .none: Color.black
            case let .ringing(ring, sounding, snoozedUntil):
                RingingView(ring: ring, sounding: sounding, snoozedUntil: snoozedUntil).id(ring.id)
            // Keyed by ring and kind: an upgrade to a newer ring (C3), or the fall back to math (C4),
            // starts the challenge over.
            case let .challenge(open): ChallengeHostView(challenge: open).id(open)
            case let .awakeCheck(ring): AwakeCheckView(ring: ring).id(ring.id)
            case let .released(record): ReleasedView(record: record).id(record.morning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.enamel)
        .foregroundStyle(Theme.face)
        .tint(Theme.face)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}

/// The ring itself: the time, the dial with the disc parked at twelve, and what Stop means now.
/// Everything comes from the engine's screen: the ring, whether it sounds, and the snoozed time (D1).
struct RingingView: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 72
    let ring: Ring
    let sounding: Bool
    /// Set when a snoozable ring is not sounding: "Snoozed until h:mm" with Start challenge (D1).
    let snoozedUntil: Date?

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
                if let snoozedUntil {
                    Text("Snoozed until \(snoozedUntil.shortTime)")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("ringing.snoozedUntil")
                }
                Text(headline)
                    .font(snoozedUntil == nil ? .title2.weight(.semibold) : .title3)
                    .foregroundStyle(snoozedUntil == nil ? Theme.face : Theme.graphite)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ringing.headline")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                ForEach(RingingButton.buttons(for: ring, sounding: sounding), id: \.self, content: button)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private func button(_ kind: RingingButton) -> some View {
        switch kind {
        case .stopNudge:
            Button("Stop") { model.dismissNudge(ring) }
                .buttonStyle(.slab)
                .accessibilityIdentifier("ringing.stop")
        case .startChallenge:
            Button("Start challenge") { model.startChallenge(ring) }
                .buttonStyle(.slab)
                .accessibilityIdentifier("ringing.up")
        case .snooze:
            Button(snoozeTitle) { model.snooze(ring) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("ringing.snooze")
        case .solve:
            Button("Solve to stop") { model.startChallenge(ring) }
                .buttonStyle(.slab)
                .accessibilityIdentifier("ringing.solve")
        }
    }

    private var headline: String {
        let p = model.position(of: ring)
        if ring.kind == .nudge { return "Ideal at \(ring.morning.shortTime). This one stops with a tap." }
        guard ring.allowsSnooze else {
            return "Ring \(p.number) of \(p.total). Past the deadline, only the challenge stops it."
        }
        let deadline = p.deadline.map { " Deadline \($0.shortTime)." } ?? ""
        return "Ring \(p.number) of \(p.total).\(deadline)"
    }

    private var snoozeTitle: String {
        let next = model.latchedRings(of: ring.morning).first { $0.date > ring.date }
        return next.map { "Snooze until \($0.date.shortTime)" } ?? "Snooze"
    }
}

/// The morning's rings on the dial, the sounding one in red, disc parked at twelve.
struct RingDial: View {
    @Environment(AppModel.self) private var model
    let ring: Ring

    var body: some View {
        let latched = model.latchedRings(of: ring.morning)
        MorningDial(dates: latched.map(\.date), latched: ring.latched,
                    activeIndex: latched.firstIndex { $0.id == ring.id })
    }
}

/// "Still up?" a few minutes after the challenge.
struct AwakeCheckView: View {
    @Environment(AppModel.self) private var model
    let ring: Ring

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
                // The engine's own checks, so the times are right under any timing. Screenshot mode has none.
                let checks = model.pendingAwakeChecks.map(\.shortTime)
                if !checks.isEmpty {
                    Text("Awake checks at \(checks.joined(separator: " and ")).")
                        .foregroundStyle(Theme.graphite)
                        .accessibilityIdentifier("released.checks")
                } else if model.demoNow != nil, model.settings.awakeChecks {
                    Text("Awake checks in 5 and 12 minutes.").foregroundStyle(Theme.graphite)
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
