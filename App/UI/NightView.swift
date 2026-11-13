import SwiftUI
import UIKit

/// Bedside mode: a dim dial and the time, screen kept on while charging, so the
/// morning alarm rings full screen in Wakelatch instead of as the system alert.
struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var charging = false
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 64

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 28) {
                    MorningDial(dates: model.nextMorning?.rings.map(\.date) ?? [], latched: true)
                        .frame(maxWidth: 220)
                    Text(context.date.shortTime)
                        .font(.system(size: min(clockSize, 96), weight: .semibold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let first = model.nextMorning?.rings.first {
                        Text("First ring \(first.date.shortTime).")
                            .font(.title3)
                    }
                }
                // Dim the bedside clock as one layer so the red disc stays solid.
                .compositingGroup()
                .opacity(0.55)
                Spacer()
                Text(charging || !model.settings.bedsideKeepsScreenOn
                     ? "Tap anywhere to leave."
                     : "Plug in to keep the screen on. Tap anywhere to leave.")
                    .font(.footnote)
                    .foregroundStyle(Theme.graphite)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.face)
        .background(Color.black)
        .contentShape(.rect)
        .onTapGesture { model.bedside = false }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Leaves bedside mode")
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refresh() }
    }

    private func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
    }

    private func refresh() {
        let state = UIDevice.current.batteryState
        charging = state == .charging || state == .full
        UIApplication.shared.isIdleTimerDisabled = model.settings.bedsideKeepsScreenOn && charging
    }

    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
