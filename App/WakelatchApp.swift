import SwiftUI
import UIKit

@main
struct WakelatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    init() {
        AppModel.shared.applyLaunchArguments(ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await AlarmService.watch { ids in
                        model.alarmsRinging(ids, appActive: UIApplication.shared.applicationState == .active)
                    }
                }
                .task { await AlarmService.watchAuthorization { model.refreshAuthorization() } }
                .task(id: scenePhase) {
                    // While open, re-check every few seconds so a due ring shows even without an alarm event.
                    while scenePhase == .active && !Task.isCancelled {
                        model.evaluate()
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        model.refreshAuthorization()
                        if model.settings.onboarded && !AlarmService.isAuthorized && !AlarmService.isDenied {
                            _ = await model.requestAlarms()
                        }
                        await model.sync()
                        model.evaluate()
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.onboarded {
                TomorrowView()
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.face)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: .constant(model.screen != .none || model.bedside)) {
            Group {
                if model.screen != .none { MorningView() } else { NightView() }
            }
            .environment(model)
        }
    }
}
