import SwiftUI
import WakelatchCore

struct ChallengePickerView: View {
    @Environment(AppModel.self) private var model
    let slot: ChallengeSlot

    private var selected: ChallengeKind {
        slot == .snooze ? model.settings.snoozeChallenge : model.settings.deadlineChallenge
    }

    private var level: Int { slot == .snooze ? 2 : 3 }

    var body: some View {
        List {
            Section {
                ForEach(ChallengeKind.allCases) { kind in
                    let available = Capabilities.supports(kind)
                    Button {
                        model.update {
                            if slot == .snooze { $0.snoozeChallenge = kind } else { $0.deadlineChallenge = kind }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kind.symbol)
                                .font(.title3)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).font(.body.weight(.semibold))
                                Text(available ? kind.summary(level: level) : Capabilities.unavailableReason(kind))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.graphite)
                            }
                            Spacer()
                            if kind == selected {
                                Image(systemName: "checkmark").font(.body.weight(.semibold))
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .accessibilityIdentifier("challenge.\(kind.rawValue)")
                }
            } footer: {
                Text(slot == .snooze
                     ? "Used for \"I'm up\" before the deadline. Later rings ask for a little more."
                     : "Used from the deadline on. Pick one that gets you out of bed.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.enamel)
        .navigationTitle(slot == .snooze ? "Before the deadline" : "At the deadline")
        .navigationBarTitleDisplayMode(.inline)
    }
}
