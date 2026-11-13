import SwiftUI
import WakelatchCore

/// First run: what Wakelatch does, alarm permission, three tips, then the two times.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var ideal = ClockTime(hour: 6, minute: 40).date
    @State private var deadline = ClockTime(hour: 7, minute: 10).date
    @State private var alarmsDenied = false

    enum Step { case welcome, alarms, tips, times }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .background(Theme.enamel)
        .foregroundStyle(Theme.face)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(primaryTitle, action: next)
                    .buttonStyle(.slab)
                    .accessibilityIdentifier("onboarding.next")
                if step == .alarms && alarmsDenied {
                    Button("Open Settings") { openSystemSettings() }
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            StationDial(rings: [0, 0.25, 0.4, 0.55, 0.7], latched: true)
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity)
            Text("Wakelatch").font(.largeTitle.weight(.bold))
            Text("Set two times. **Ideal** is when you'd like to be up. **Deadline** is when you have to be.")
                .font(.title3)
            Text("From Ideal on, Wakelatch keeps ringing until you solve a challenge. Before the deadline, Stop snoozes. From the deadline, only the challenge stops it.")
                .foregroundStyle(Theme.graphite)
        case .alarms:
            heading("Allow alarms", symbol: "alarm")
            Text("Wakelatch uses iOS alarms, so it rings through silent mode and Focus, on your Apple Watch too, and even if the app is closed or the phone restarts.")
            if alarmsDenied {
                Label("Alarms are off for Wakelatch. Turn them on in Settings, then come back.", systemImage: "exclamationmark.triangle")
            }
        case .tips:
            heading("Before tomorrow", symbol: "checklist")
            tip("speaker.wave.3", "Turn your ringer volume up.", "Alarms play at ringer volume. iOS doesn't let apps change it.")
            tip("eye.slash", "Don't hide or lock Wakelatch.", "iOS doesn't ring alarms from hidden or Face ID-locked apps.")
            tip("bolt.fill", "Leave it open on the charger.", "Start Bedside mode at night for the full-screen Wakelatch alarm instead of the system one.")
        case .times:
            heading("Your two times", symbol: "clock")
            timePicker("Ideal", "When you'd like to be up", $ideal)
            timePicker("Deadline", "When you must be up", $deadline)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func heading(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.largeTitle.weight(.bold)).labelStyle(.titleOnly)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(Theme.graphite)
            }
        }
    }

    private func timePicker(_ title: String, _ caption: String, _ value: Binding<Date>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(caption).font(.subheadline).foregroundStyle(Theme.graphite)
            }
            Spacer()
            DatePicker(title, selection: value, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityIdentifier("onboarding.\(title.lowercased())")
        }
        .padding(14)
        .background(Theme.face.opacity(0.08), in: .rect(cornerRadius: Theme.radius))
    }

    private var chosenTimes: WakeTimes {
        func clock(_ d: Date) -> ClockTime {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
        }
        return WakeTimes(ideal: clock(ideal), deadline: clock(deadline))
    }

    private var problem: String? {
        chosenTimes.windowMinutes > MorningPlan.maxWindowMinutes ? "Deadline must be within 3 hours of Ideal." : nil
    }

    private var primaryTitle: String {
        switch step {
        case .welcome, .tips: "Continue"
        case .alarms: alarmsDenied ? "Continue without alarms" : "Allow alarms"
        case .times: "Set alarm"
        }
    }

    private func next() {
        switch step {
        case .welcome: step = .alarms
        case .alarms:
            if alarmsDenied { step = .tips; return }
            Task {
                if await model.requestAlarms() { step = .tips } else { alarmsDenied = true }
            }
        case .tips: step = .times
        case .times:
            guard problem == nil else { return }
            model.update {
                $0.times = chosenTimes
                $0.onboarded = true
            }
        }
    }
}
