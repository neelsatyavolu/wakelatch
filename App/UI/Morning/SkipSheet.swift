import SwiftUI
import WakelatchCore

/// Ends this morning's alarm without the challenge. Two a month, by typing a sentence.
struct SkipSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ring: Ring
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("For when the challenge can't be done. This ends the rest of this morning's alarm.")
                    LabeledContent("Left this month", value: "\(model.skipsLeft) of \(SkipLedger.perMonth)")
                }
                if model.skipsLeft > 0 {
                    Section {
                        TextField("Type the sentence", text: $text, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("skip.text")
                    } header: {
                        Text("Type: \(SkipLedger.phrase)")
                    }
                    Section {
                        Button("Skip this morning", role: .destructive) {
                            if model.skip(ring) { dismiss() }
                        }
                        .disabled(!SkipLedger.phraseMatches(text))
                        .accessibilityIdentifier("skip.confirm")
                    }
                } else {
                    Section { Text("No skips left until next month.") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.enamel)
            .navigationTitle("Emergency skip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("skip.cancel")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
