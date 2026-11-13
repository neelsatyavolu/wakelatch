import Foundation
import Observation
import UIKit
import WakelatchCore

/// What the morning screens are showing, if anything.
enum MorningScreen: Equatable {
    case none
    /// A ring is due. `sounding` is true when it is ringing right now.
    case ringing(ScheduledRing, sounding: Bool)
    case challenge(ScheduledRing)
    case awakeCheck(ScheduledRing)
    case released(MorningRecord)
}

/// App state: settings, the alarms on the system, and the morning in progress.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private let storage = Storage()
    let calendar = Calendar.current

    private(set) var settings: UserSettings
    private(set) var rings: [ScheduledRing]
    private(set) var records: [MorningRecord]
    private(set) var skips: SkipLedger
    /// Rings the user snoozed, and awake checks they answered.
    private(set) var acknowledged: Set<UUID>
    var screen: MorningScreen = .none
    /// Bedside mode is showing (it shares the full-screen cover with the morning screens).
    var bedside = false
    private(set) var scheduleError: String?
    private(set) var syncing = false
    private var resyncRequested = false
    /// Alarm IDs iOS reported after the last sync.
    private(set) var confirmedWithSystem: Set<UUID>?
    /// AlarmKit permission, kept current by `watchAuthorization`.
    private(set) var alarmsAuthorized = false
    /// Screenshot mode: keeps the demo screen up.
    private var demo = false
    /// Screenshot mode: the time the morning screens show.
    private(set) var demoNow: Date?

    private init() {
        settings = storage.load(UserSettings.self, key: "settings") ?? UserSettings()
        rings = storage.load([ScheduledRing].self, key: "rings") ?? []
        records = storage.load([MorningRecord].self, key: "records") ?? []
        skips = storage.load(SkipLedger.self, key: "skips") ?? SkipLedger()
        acknowledged = storage.load(Set<UUID>.self, key: "acknowledged") ?? []
    }

    // MARK: settings

    func update(_ change: (inout UserSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        storage.save(settings, key: "settings")
        Task { await sync() }
    }

    /// Validation message for the chosen times, or nil when they work.
    var timesProblem: String? {
        settings.times.windowMinutes > MorningPlan.maxWindowMinutes
            ? "Deadline must be within 3 hours of Ideal." : nil
    }

    // MARK: permission

    func refreshAuthorization() {
        alarmsAuthorized = AlarmService.isAuthorized
    }

    func requestAlarms() async -> Bool {
        let granted = await AlarmService.requestAuthorization()
        refreshAuthorization()
        return granted
    }

    // MARK: schedule

    /// The next morning that will ring, and its rings.
    var nextMorning: (day: Date, rings: [PlannedRing])? {
        guard settings.enabled, timesProblem == nil else { return nil }
        let days = MorningPlan.upcomingDays(after: .now, times: settings.times, repeatDays: settings.repeatDays,
                                            count: 1, nudges: settings.plan.nudges, calendar: calendar)
        guard let day = days.first,
              let plan = try? MorningPlan.build(on: day, times: settings.times, options: settings.plan, calendar: calendar)
        else { return nil }
        return (day, plan)
    }

    /// Replaces scheduled alarms with the next three mornings, keeping a morning already under way.
    func sync() async {
        guard AlarmService.isAuthorized, !demo else { return }
        // A change made while a sync is running must not be dropped: run again with the new settings.
        guard !syncing else { resyncRequested = true; return }
        syncing = true
        // Finish handing alarms to iOS even if the user leaves the app mid-sync.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Schedule alarms")
        defer {
            syncing = false
            UIApplication.shared.endBackgroundTask(background)
        }
        repeat {
            resyncRequested = false
            await syncOnce()
        } while resyncRequested
    }

    private func syncOnce() async {
        let now = Date.now
        closeFinishedMornings(now: now)
        let active = activeMorning(at: now)
        let keep = rings.filter { $0.morning == active || ($0.kind == .awakeCheck && $0.date > now) }
        for ring in rings where !keep.contains(ring) { AlarmService.cancel(ring.id) }

        var next = keep
        scheduleError = nil
        if settings.enabled, timesProblem == nil {
            let days = MorningPlan.upcomingDays(after: now, times: settings.times, repeatDays: settings.repeatDays,
                                                count: 3, nudges: settings.plan.nudges, calendar: calendar)
            for day in days {
                let morning = MorningPlan.idealDate(on: day, times: settings.times, calendar: calendar)
                guard morning != active,
                      let plan = try? MorningPlan.build(on: day, times: settings.times, options: settings.plan,
                                                        calendar: calendar) else { continue }
                for planned in plan where planned.date > now {
                    let ring = ScheduledRing(planned: planned, morning: morning)
                    do {
                        try await AlarmService.schedule(ring)
                        next.append(ring)
                    } catch {
                        scheduleError = "Couldn't schedule every alarm: \(error.localizedDescription)"
                    }
                }
            }
        }
        rings = next.sorted { $0.date < $1.date }
        storage.save(rings, key: "rings")
        let known = Set(rings.map(\.id))
        for id in AlarmService.systemAlarmIDs() where !known.contains(id) { AlarmService.cancel(id) }
        confirmedWithSystem = AlarmService.systemAlarmIDs()
    }

    /// Rings of the next morning that iOS really has on its books (nil before the first sync).
    var confirmedNextRings: Int? {
        guard let confirmed = confirmedWithSystem, let day = nextMorning?.day else { return nil }
        let morning = MorningPlan.idealDate(on: day, times: settings.times, calendar: calendar)
        return rings.filter { $0.morning == morning && confirmed.contains($0.id) }.count
    }

    /// A morning whose latch has started and isn't finished.
    func activeMorning(at now: Date) -> Date? {
        let started = rings.filter { $0.latched && $0.date <= now }
        for morning in Set(started.map(\.morning)).sorted(by: >) {
            let last = rings.filter { $0.morning == morning && $0.latched }.map(\.date).max() ?? morning
            if now <= last.addingTimeInterval(10 * 60) { return morning }
        }
        return nil
    }

    /// Records mornings whose last ring passed without a solve, and drops their rings.
    private func closeFinishedMornings(now: Date) {
        let active = activeMorning(at: now)
        let past = Set(rings.filter { $0.latched && $0.morning != active }.map(\.morning))
            .filter { morning in rings.filter { $0.morning == morning && $0.latched }.allSatisfy { $0.date < now } }
        for morning in past { record(morning: morning, upAt: nil, skipped: false) }
        rings.removeAll { past.contains($0.morning) && $0.kind != .awakeCheck }
        rings.removeAll { $0.kind == .awakeCheck && $0.date < now.addingTimeInterval(-15 * 60) }
    }

    // MARK: morning flow

    /// Decides which morning screen to show. `sounding` holds alarms ringing right now.
    func evaluate(now: Date = .now, sounding: Set<UUID> = []) {
        guard !demo else { return }
        switch screen {
        case .challenge, .released: return
        default: break
        }
        let checks = rings.filter { $0.kind == .awakeCheck && $0.date <= now && !acknowledged.contains($0.id) }
        if let check = checks.max(by: { $0.date < $1.date }) {
            screen = .awakeCheck(check)
            return
        }
        if let morning = activeMorning(at: now),
           let due = rings.filter({ $0.morning == morning && $0.latched && $0.date <= now })
               .max(by: { $0.date < $1.date }),
           !acknowledged.contains(due.id) {
            screen = .ringing(due, sounding: sounding.contains(due.id) || now.timeIntervalSince(due.date) < 90)
            return
        }
        if let nudge = rings.first(where: { $0.kind == .nudge && sounding.contains($0.id) }) {
            screen = .ringing(nudge, sounding: true)
            return
        }
        if case .ringing = screen { screen = .none }
        if case .awakeCheck = screen { screen = .none }
    }

    /// AlarmKit reports alarms ringing while Wakelatch is open: take over with the in-app screen.
    func alarmsRinging(_ ids: Set<UUID>, appActive: Bool) {
        let ours = ids.intersection(rings.map(\.id))
        guard appActive, !ours.isEmpty else { return }
        evaluate(sounding: ours)
        guard case let .ringing(ring, _) = screen else { return }
        // The system alarm is only silenced once Wakelatch's own sound is really playing loud enough;
        // otherwise both ring, which is better than neither.
        RingPlayer.shared.play(nudge: ring.kind == .nudge)
        guard RingPlayer.shared.isAudible else { return }
        for id in ours { AlarmService.silence(id) }
    }

    func snooze(_ ring: ScheduledRing) {
        acknowledge(ring.id)
        screen = .none
    }

    func dismissNudge(_ ring: ScheduledRing) {
        acknowledge(ring.id)
        screen = .none
    }

    func startChallenge(_ ring: ScheduledRing) {
        screen = .challenge(ring)
    }

    func solved(_ ring: ScheduledRing) {
        let now = Date.now
        let record = finish(morning: ring.morning, upAt: now, skipped: false)
        if settings.awakeChecks { Task { await scheduleAwakeChecks(after: now, morning: ring.morning) } }
        screen = .released(record)
        bedside = false
    }

    /// Emergency skip. Returns false when none are left this month.
    func skip(_ ring: ScheduledRing) -> Bool {
        guard skips.use(at: .now, calendar: calendar) else { return false }
        storage.save(skips, key: "skips")
        _ = finish(morning: ring.morning, upAt: nil, skipped: true)
        screen = .none
        return true
    }

    var skipsLeft: Int { skips.remaining(at: .now, calendar: calendar) }

    /// The latched rings of a morning, in order.
    func latchedRings(of morning: Date) -> [ScheduledRing] {
        rings.filter { $0.morning == morning && $0.latched }.sorted { $0.date < $1.date }
    }

    /// "Ring 3 of 10" numbers and the deadline for a ring's morning.
    func position(of ring: ScheduledRing) -> (number: Int, total: Int, deadline: Date?) {
        let latched = latchedRings(of: ring.morning)
        let number = (latched.firstIndex { $0.id == ring.id } ?? 0) + 1
        return (number, latched.count, latched.first { $0.kind == .deadline }?.date)
    }

    func confirmAwake(_ ring: ScheduledRing) {
        let group = rings.filter { $0.kind == .awakeCheck && $0.checkGroup == ring.checkGroup && $0.morning == ring.morning }
        for check in group {
            AlarmService.cancel(check.id)
            acknowledge(check.id)
        }
        rings.removeAll { group.contains($0) }
        storage.save(rings, key: "rings")
        screen = .none
    }

    func closeReleased() {
        screen = .none
    }

    var pendingAwakeChecks: [Date] {
        rings.filter { $0.kind == .awakeCheck }.reduce(into: [Int: Date]()) { first, ring in
            if let g = ring.checkGroup, first[g].map({ ring.date < $0 }) ?? true { first[g] = ring.date }
        }.values.sorted()
    }

    private func acknowledge(_ id: UUID) {
        acknowledged.insert(id)
        storage.save(acknowledged, key: "acknowledged")
    }

    private func finish(morning: Date, upAt: Date?, skipped: Bool) -> MorningRecord {
        let record = record(morning: morning, upAt: upAt, skipped: skipped)
        let mine = rings.filter { $0.morning == morning && $0.kind != .awakeCheck }
        for ring in mine { AlarmService.cancel(ring.id) }
        rings.removeAll { mine.contains($0) }
        storage.save(rings, key: "rings")
        acknowledged.subtract(mine.map(\.id))
        storage.save(acknowledged, key: "acknowledged")
        Task { await sync() }
        return record
    }

    @discardableResult
    private func record(morning: Date, upAt: Date?, skipped: Bool) -> MorningRecord {
        let deadline = rings.first { $0.morning == morning && $0.kind == .deadline }?.date ?? morning
        let record = MorningRecord(morning: morning, ideal: morning, deadline: deadline, upAt: upAt, skipped: skipped)
        records.removeAll { $0.morning == morning }
        records.append(record)
        records = Array(records.sorted { $0.morning < $1.morning }.suffix(60))
        storage.save(records, key: "records")
        return record
    }

    private func scheduleAwakeChecks(after solved: Date, morning: Date) async {
        for (group, dates) in AwakeChecks.plan(solvedAt: solved).enumerated() {
            for date in dates {
                let ring = ScheduledRing(date: date, kind: .awakeCheck, level: 0, morning: morning, checkGroup: group)
                if (try? await AlarmService.schedule(ring)) != nil { rings.append(ring) }
            }
        }
        rings.sort { $0.date < $1.date }
        storage.save(rings, key: "rings")
    }

    // MARK: history

    /// "Up by Ideal on 3 of the last 5 mornings." Nil until there's a morning to count.
    var historyLine: String? {
        let recent = records.filter { !$0.skipped }.suffix(7)
        guard !recent.isEmpty else { return nil }
        let up = recent.filter(\.upByIdeal).count
        return "Up by Ideal on \(up) of the last \(recent.count) mornings."
    }

    // MARK: testing

    /// UI-test hooks. `-uitest-reset` clears everything; `-uitest-soon` sets Ideal to the next minute
    /// with a two-minute window and no nudges.
    func applyLaunchArguments(_ args: [String]) {
        if args.contains("-uitest-reset") {
            AlarmService.cancelAll()
            storage.removeAll()
            settings = UserSettings()
            rings = []
            records = []
            skips = SkipLedger()
            acknowledged = []
        }
        if args.contains("-uitest-onboarded") { settings.onboarded = true }
        if args.contains("-uitest-soon") {
            let start = Date.now.addingTimeInterval(Calendar.current.component(.second, from: .now) > 35 ? 120 : 60)
            let c = Calendar.current.dateComponents([.hour, .minute], from: start)
            let end = Calendar.current.dateComponents([.hour, .minute], from: start.addingTimeInterval(120))
            settings.times = WakeTimes(ideal: ClockTime(hour: c.hour!, minute: c.minute!),
                                       deadline: ClockTime(hour: end.hour!, minute: end.minute!))
            settings.plan = PlanOptions(nudges: false, snoozeMinutes: 3, guardRings: 15)
            settings.repeatDays = []
        }
        storage.save(settings, key: "settings")
        if let show = args.first(where: { $0.hasPrefix("-uitest-show=") })?.split(separator: "=").last {
            showDemo(String(show))
        }
    }

    /// Screenshot mode: puts a morning screen up with a sample ring that isn't scheduled.
    private func showDemo(_ name: String) {
        demo = true
        let morning = MorningPlan.idealDate(on: .now, times: settings.times, calendar: calendar)
        let plan = (try? MorningPlan.build(on: .now, times: settings.times, options: settings.plan, calendar: calendar)) ?? []
        rings = plan.map { ScheduledRing(planned: $0, morning: morning) }
        let latched = latchedRings(of: morning)
        let ring = latched.first { $0.kind == .snooze && $0.date.timeIntervalSince(morning) >= 18 * 60 } ?? latched[0]
        let deadline = latched.first { $0.kind == .deadline } ?? ring
        demoNow = ring.date
        switch name {
        case "ringing": screen = .ringing(ring, sounding: false)
        case "challenge": screen = .challenge(ring)
        case "released":
            screen = .released(MorningRecord(morning: morning, ideal: morning, deadline: deadline.date,
                                             upAt: morning.addingTimeInterval(12 * 60)))
        case "night": bedside = true
        default: break
        }
    }
}
