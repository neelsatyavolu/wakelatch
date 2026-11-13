import SwiftUI

@main
struct SpikeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let store = LatchStore.shared

    init() {
        // UI tests start from a clean slate: no chain, no log, no system alarms.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            AlarmLab.cancelAll()
            LatchStore.shared.resetAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await autoArmIfAsked() }
                .task { await AlarmLab.watchForRings() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    store.reload()
                    store.record("app active; \(AlarmLab.scheduledCount()) alarms on the system")
                    store.latchIfDue(reason: "app opened")
                }
        }
    }

    /// `-autoarm` arms a short chain on launch and prints what AlarmKit says,
    /// for checking the system side without driving the UI.
    @MainActor
    private func autoArmIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-autoarm") else { return }
        print("autoarm: auth before = \(AlarmLab.authorization)")
        do {
            let state = try await AlarmLab.requestAuthorization()
            print("autoarm: auth = \(state)")
            let count = try await AlarmLab.armChain(delay: 30, interval: 60, guards: 2)
            print("autoarm: scheduled \(count), system has \(AlarmLab.scheduledCount())")
        } catch {
            print("autoarm: error \(error)")
        }
        for line in store.log.prefix(5) { print("autoarm log: \(line)") }
    }
}
