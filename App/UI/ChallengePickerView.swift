import SwiftUI
import WakelatchCore

struct ChallengePickerView: View {
    @Environment(AppModel.self) private var model
    let slot: ChallengeSlot
    /// Kinds this phone can run. Read again after each permission prompt, so a refusal shows at once.
    @State private var usable = Self.usableKinds()

    private var selected: ChallengeKind {
        slot == .snooze ? model.settings.snoozeChallenge : model.settings.deadlineChallenge
    }

    private var level: Int { slot == .snooze ? 2 : 3 }

    var body: some View {
        List {
            Section {
                ForEach(ChallengeKind.allCases) { kind in
                    let available = usable.contains(kind)
                    Button {
                        Task { await choose(kind) }
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
        .onAppear { usable = Self.usableKinds() }
    }

    /// Asks for the camera or motion permission now, not during the alarm (fix 6). A refused kind is
    /// not chosen; if it is refused later, the morning's challenge falls back to math.
    private func choose(_ kind: ChallengeKind) async {
        let granted = await Capabilities.requestAccess(kind)
        usable = Self.usableKinds()
        guard granted else { return }
        model.update {
            if slot == .snooze { $0.snoozeChallenge = kind } else { $0.deadlineChallenge = kind }
        }
    }

    private static func usableKinds() -> Set<ChallengeKind> {
        Set(ChallengeKind.allCases.filter(Capabilities.supports))
    }
}
