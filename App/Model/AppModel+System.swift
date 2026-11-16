import Foundation
import SwiftUI
import UIKit
import WakelatchCore

/// Turns what iOS reports (scene phase, AlarmKit updates, battery, clock and calendar changes) into events.
extension AppModel {
    /// Starts watching AlarmKit, the battery and the calendar. Called once by the app.
    func start() {
        guard demo == nil, background.isEmpty else { return }
        background.append(Task { [weak self] in await self?.refreshAuthorization() })
        let alarms = environment.alarms
        background.append(Task { [weak self] in
            for await table in alarms.alarmUpdates() { self?.alarmTableChanged(table) }
        })
        background.append(Task { [weak self] in
            await AlarmAuthorization.watch { self?.applyAuthorization($0) }
        })
        UIDevice.current.isBatteryMonitoringEnabled = true
        observe(UIDevice.batteryStateDidChangeNotification) { model in
            model.chargingChanged(model.environment.isCharging())
        }
        let calendarNotices: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
                                                    UIApplication.significantTimeChangeNotification,
                                                    NSLocale.currentLocaleDidChangeNotification]
        for name in calendarNotices {
            observe(name) { model in model.calendarChanged() }
        }
    }

    /// `launched` on this process's first activation, `becameActive` after that; `enteredBackground` when it
    /// leaves. A process an intent started in the background gets `launched` when it is first opened.
    func scenePhaseChanged(_ phase: ScenePhase) {
        guard demo == nil else { return }
        switch phase {
        case .active:
            lastAlerting = nil
            send(hasLaunched ? .becameActive(now: now) : .launched(now: now))
            hasLaunched = true
            send(.chargingChanged(environment.isCharging(), now: now))
            startTicking()
        case .background:
            tickTask?.cancel()
            tickTask = nil
            lastAlerting = nil
            send(.enteredBackground(now: now))
        default:
            break
        }
    }

    func chargingChanged(_ charging: Bool) {
        send(.chargingChanged(charging, now: now))
    }

    func calendarChanged() {
        NSTimeZone.resetSystemTimeZone()
        send(.calendarChanged(environment.calendar(), now: now))
    }

    private func startTicking() {
        tickTask?.cancel()
        let interval = environment.tickInterval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                send(.tick(now: now))
            }
        }
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (AppModel) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        }
        observers.append(token)
    }
}
