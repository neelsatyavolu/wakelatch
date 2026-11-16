import SwiftUI
import WakelatchCore

/// Presents the morning screens (or Bedside) full screen over home or onboarding.
///
/// The engine closes home sheets before a ring takes the screen (F6), but UIKit refuses to present while a
/// sheet is still sliding away, and a refused cover never comes back on its own. So the cover is presented
/// again every second until it has really appeared (test U10).
struct MorningCover: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var presented = false

    static let retryInterval: Duration = .seconds(1)

    private var wanted: Bool { model.screen.isShowing || model.bedside }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $presented) {
                Group {
                    if model.screen.isShowing { MorningView() } else { NightView() }
                }
                .environment(model)
                .overlay(alignment: .topLeading) { DebugStateProbe(json: model.debugJSON) }
                .onAppear { model.coverAppeared() }
                .onDisappear { model.coverDisappeared() }
            }
            .task(id: wanted) { await follow(wanted) }
    }

    private func follow(_ wanted: Bool) async {
        guard wanted else {
            presented = false
            return
        }
        while !Task.isCancelled, !model.coverVisible {
            presented = true
            try? await Task.sleep(for: Self.retryInterval)
            guard !Task.isCancelled, !model.coverVisible else { return }
            presented = false
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// UI tests only: a hidden element whose value is the model's state as JSON (`DebugState`).
struct DebugStateProbe: View {
    let json: String?

    var body: some View {
        if let json {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("debug")
                .accessibilityValue(json)
                .accessibilityIdentifier("debug.state")
        }
    }
}
