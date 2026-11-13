import SwiftUI

/// Everything the spike saw, newest first. Read it after a force-quit or
/// reboot test to see which rings fired and which intents ran.
struct LogView: View {
    @Environment(LatchStore.self) private var store

    var body: some View {
        List {
            if store.log.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "clock",
                                       description: Text("Arm a latch and the rings, stops and solves show up here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(store.log.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote.monospacedDigit())
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.enamel)
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: store.log.joined(separator: "\n")) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Clear log", role: .destructive) { store.clearLog() }
                    .disabled(store.log.isEmpty)
            }
        }
    }
}
