import SwiftUI
import WakelatchCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Snooze rings every", selection: binding(\.plan.snoozeMinutes)) {
                        ForEach([5, 9, 15], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Nudges before Ideal", isOn: binding(\.plan.nudges))
                    Toggle("Awake checks", isOn: binding(\.awakeChecks))
                } header: {
                    Text("Alarm")
                } footer: {
                    Text("Nudges ring softly 20 and 10 minutes before Ideal and stop with one tap. Awake checks ring 5 and 12 minutes after you solve the challenge and need one tap.")
                }

                Section {
                    Toggle("Keep screen on while charging", isOn: binding(\.bedsideKeepsScreenOn))
                } header: {
                    Text("Bedside mode")
                } footer: {
                    Text("With the screen on, Wakelatch rings full screen with its own sound. If the screen locks, the system alarm rings instead.")
                }

                Section {
                    LabeledContent("Left this month", value: "\(model.skipsLeft) of \(SkipLedger.perMonth)")
                } header: {
                    Text("Emergency skips")
                } footer: {
                    Text("For when a challenge can't be done, like a broken camera. Each skip ends the morning's alarm after you type a sentence.")
                }

                Section("Permissions") {
                    LabeledContent("Alarms", value: model.alarmsAuthorized ? "On" : "Off")
                    if !model.alarmsAuthorized {
                        Button("Open Settings") { openSystemSettings() }
                    }
                }

                Section {
                    Text("Nothing leaves your phone. No accounts, no analytics, no ads, no network.")
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    Link("Source code (MIT)", destination: URL(string: "https://github.com/neelsatyavolu/wakelatch")!)
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.enamel)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func binding<T: Equatable>(_ path: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: path] }, set: { value in model.update { $0[keyPath: path] = value } })
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
