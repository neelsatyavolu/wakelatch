@preconcurrency import AlarmKit
import Foundation
import SwiftUI
import WakelatchCore

/// AlarmKit experiments for the spike.
@MainActor
enum AlarmLab {
    private static var manager: AlarmManager { .shared }

    static var authorization: AlarmManager.AuthorizationState { manager.authorizationState }

    static func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await manager.requestAuthorization()
    }

    static func scheduledCount() -> Int {
        (try? manager.alarms.count) ?? -1
    }

    // MARK: (c) guard chain

    /// Schedules the first ring after `delay` and `guards` more rings every
    /// `interval` seconds. Returns how many were accepted by the system.
    static func armChain(delay: TimeInterval, interval: TimeInterval, guards: Int) async throws -> Int {
        let chain = try GuardChain(firstFire: .now.addingTimeInterval(delay), interval: interval, guardCount: guards)
        cancelChain()
        var ids: [UUID] = []
        var dates: [Date] = []
        for (index, date) in chain.fireDates.enumerated() {
            let id = UUID()
            let title: LocalizedStringResource = index == 0 ? "Wakelatch spike" : "Guard ring \(index)"
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(at: date, title: title, id: id))
                ids.append(id)
                dates.append(date)
            } catch {
                LatchStore.shared.record("ring \(index) refused: \(error)")
                break
            }
        }
        LatchStore.shared.setChain(ids, dates: dates)
        LatchStore.shared.setChallengePending(false)
        return ids.count
    }

    /// Stops a ringing alarm and cancels the rest of the chain.
    static func cancelChain() {
        for id in LatchStore.shared.chainIDs {
            try? manager.stop(id: id)
            try? manager.cancel(id: id)
        }
        LatchStore.shared.setChain([], dates: [])
    }

    /// While the app runs, a chain alarm starting to ring latches the challenge.
    static func watchForRings() async {
        for await alarms in manager.alarmUpdates {
            let chain = Set(LatchStore.shared.chainIDs)
            if alarms.contains(where: { $0.state == .alerting && chain.contains($0.id) }) {
                LatchStore.shared.latchIfDue(reason: "alarm ringing")
            }
        }
    }

    /// Cancels every alarm this app has on the system.
    static func cancelAll() {
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.stop(id: alarm.id)
            try? manager.cancel(id: alarm.id)
        }
    }

    // MARK: (a) per-app cap

    /// Schedules far-future alarms until AlarmKit refuses, then cancels them.
    static func probeCap(limit: Int = 300) async -> String {
        let base = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        var ids: [UUID] = []
        var outcome = "no refusal up to \(limit)"
        for i in 0..<limit {
            let id = UUID()
            do {
                let date = base.addingTimeInterval(Double(i) * 60)
                _ = try await manager.schedule(id: id, configuration: configuration(at: date, title: "Cap probe", id: id))
                ids.append(id)
            } catch {
                outcome = "refused at #\(i + 1): \(error)"
                break
            }
        }
        let existing = LatchStore.shared.chainIDs.count
        for id in ids { try? manager.cancel(id: id) }
        return "accepted \(ids.count) (+\(existing) chain alarms already scheduled); \(outcome)"
    }

    // MARK: configuration

    private static func configuration(
        at date: Date,
        title: LocalizedStringResource,
        id: UUID
    ) -> AlarmManager.AlarmConfiguration<SpikeAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: AlarmButton(text: "Solve", textColor: .white, systemImageName: "function"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<SpikeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SpikeAlarmMetadata(role: "chain"),
            tintColor: Theme.signal
        )
        return .alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: OpenChallengeIntent(alarmID: id, source: "Stop"),
            secondaryIntent: OpenChallengeIntent(alarmID: id, source: "Solve")
        )
    }
}
