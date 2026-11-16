import SwiftUI
import UIKit
import WakelatchCore

@main
struct WakelatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Nil while the app only hosts the WakelatchTests unit tests: they build their own models.
    private let model: AppModel?

    init() {
        model = AppEnvironment.isUnitTestHost ? nil : AppModel.shared
        model?.start()
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView()
                    .environment(model)
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        model.scenePhaseChanged(phase)
                        guard phase == .active else { return }
                        Task { await model.checkAuthorization() }
                    }
            } else {
                Color.clear
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
        .overlay(alignment: .topLeading) { DebugStateProbe(json: model.debugJSON) }
        .modifier(MorningCover())
    }
}
