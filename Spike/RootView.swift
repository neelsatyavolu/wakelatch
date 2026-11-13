import SwiftUI

/// Spike home: arm a test latch, run the probes, open the log.
struct RootView: View {
    @Environment(LatchStore.self) private var store

    var body: some View {
        NavigationStack {
            ArmView()
                .navigationTitle("Latch test")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Log", value: Route.log)
                    }
                }
                .navigationDestination(for: Route.self) { _ in LogView() }
        }
        .tint(Theme.face)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: .constant(store.challengePending)) {
            ChallengeView()
        }
    }

    private enum Route: Hashable { case log }
}

extension Date {
    /// Position of this moment on a clock's minute track, 0 at twelve.
    var minuteFraction: Double {
        let parts = Calendar.current.dateComponents([.minute, .second], from: self)
        return (Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60) / 60
    }
}

private struct ArmView: View {
    @Environment(LatchStore.self) private var store
    @State private var delay: TimeInterval = 60
    @State private var interval: TimeInterval = 60
    @State private var guards = 5
    @State private var busy = false
    @State private var capResult: String?
    @State private var lockOn = RemovalLock.isLocked
    @State private var errorText: String?

    private var armed: Bool { !store.chainIDs.isEmpty }

    var body: some View {
        List {
            Section {
                StationDial(rings: store.chainDates.map(\.minuteFraction), latched: armed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .animation(.spring(duration: 0.5), value: armed)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                statusLine
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Chain") {
                Picker("First ring in", selection: $delay) {
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
                Picker("Guard rings every", selection: $interval) {
                    Text("60 s").tag(60.0)
                    Text("90 s").tag(90.0)
                }
                Stepper("Guard rings: \(guards)", value: $guards, in: 0...20)
            }

            if armed {
                Section {
                    Button("Cancel chain", role: .destructive) {
                        AlarmLab.cancelChain()
                        store.record("chain cancelled from home")
                    }
                }
            }

            Section {
                if RemovalLock.isAvailable {
                    Toggle("Block deleting the app", isOn: $lockOn)
                        .onChange(of: lockOn) { _, on in setLock(on) }
                }
                Button("Find the alarm limit", action: probeCap)
                    .disabled(busy || armed)
                if let capResult {
                    Text(capResult).font(.footnote.monospacedDigit()).foregroundStyle(Theme.graphite)
                }
            } header: {
                Text("Probes")
            } footer: {
                Text("The limit probe schedules alarms a month out and cancels them. Cancel the chain first.")
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.face)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.enamel)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaInset(edge: .bottom) {
            Button(armed ? "Re-arm latch" : "Arm latch", action: arm)
                .buttonStyle(.slab)
                .accessibilityIdentifier("home.arm")
                .disabled(busy)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let last = store.chainDates.last {
            let next = store.chainDates.first { $0 > .now } ?? last
            VStack(spacing: 4) {
                Text("Latched. \(store.chainDates.count) rings.")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("home.status")
                Text("Next ring \(next.formatted(date: .omitted, time: .shortened)). Last \(last.formatted(date: .omitted, time: .shortened)).")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.graphite)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Nothing armed.")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("home.status")
                .frame(maxWidth: .infinity)
        }
    }

    private func arm() {
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                if AlarmLab.authorization != .authorized {
                    guard try await AlarmLab.requestAuthorization() == .authorized else {
                        errorText = "Alarms are off for this app. Turn them on in Settings."
                        return
                    }
                }
                let count = try await AlarmLab.armChain(delay: delay, interval: interval, guards: guards)
                store.record("armed \(count) rings, every \(Int(interval)) s")
                if lockOn { RemovalLock.setLocked(true) }
            } catch {
                errorText = "Couldn't arm: \(error.localizedDescription)"
                store.record("arm failed: \(error)")
            }
        }
    }

    private func setLock(_ on: Bool) {
        Task {
            do {
                if on && !RemovalLock.isAuthorized { try await RemovalLock.requestAuthorization() }
                RemovalLock.setLocked(on)
                store.record("delete block \(on ? "on" : "off")")
            } catch {
                lockOn = false
                errorText = "Screen Time permission wasn't granted: \(error.localizedDescription)"
                store.record("delete block auth failed: \(error)")
            }
        }
    }

    private func probeCap() {
        busy = true
        Task {
            defer { busy = false }
            if AlarmLab.authorization != .authorized { _ = try? await AlarmLab.requestAuthorization() }
            let result = await AlarmLab.probeCap()
            capResult = result
            store.record("cap probe: \(result)")
        }
    }
}
