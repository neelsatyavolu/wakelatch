@preconcurrency import AlarmKit
import Foundation
import Observation
import WakelatchCore

/// The app shell around `MorningEngine` (plan 1.4). `send(_:)` is the single writer of morning state:
/// it runs `engine.handle`, saves the engine state before anything else happens (the `.persist` effect
/// always comes first), then performs the effects in the engine's order. AlarmKit results come back as
/// events through `send(_:)` too, so nothing is ever written back from a stale snapshot.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(environment: .live())

    private(set) var engine: MorningEngine
    private(set) var settings: UserSettings
    /// AlarmKit permission; nil until the first read lands (it is read off the main thread).
    private(set) var alarmsAuthorized: Bool?
    /// AlarmKit's table at the last read or update. Nil before the first.
    private(set) var systemTable: [SystemAlarm]?
    /// Goes up by one on each `.dismissHomeSheets`. Home views close their sheets when it changes, so the
    /// morning cover can present (contract F6).
    private(set) var sheetDismissals = 0
    /// AlarmKit calls queued or running.
    private(set) var alarmCallsInFlight = 0
    /// The morning cover (or Bedside) is on screen.
    private(set) var coverVisible = false
    /// Screenshot mode (`-uitest-show`): a sample screen that is not scheduled.
    private(set) var demo: DemoScreen?
    /// UI tests only: alert-button intents received by this install, kept across launches.
    private(set) var intentsReceived = 0
    /// The in-app sound playing now (under UI tests, the one that would be: they run silent).
    private(set) var playing: PlayingSound?

    @ObservationIgnored let environment: AppEnvironment
    @ObservationIgnored private var inbox: [Event] = []
    @ObservationIgnored private var draining = false
    /// The tail of the serial AlarmKit queue.
    @ObservationIgnored var alarmQueue: Task<Void, Never>?
    /// `launched` was sent: later activations send `becameActive`.
    @ObservationIgnored var hasLaunched = false
    @ObservationIgnored var tickTask: Task<Void, Never>?
    /// The alerting set last sent, so `.alerting` is only sent when it changes.
    @ObservationIgnored var lastAlerting: Set<UUID>?
    @ObservationIgnored var background: [Task<Void, Never>] = []
    @ObservationIgnored var observers: [any NSObjectProtocol] = []
    /// When `challengeActivity` last reached the engine, to send it at most every few seconds.
    @ObservationIgnored var lastActivitySent: Date?

    init(environment: AppEnvironment) {
        self.environment = environment
        var settings = environment.settingsStore.load(UserSettings.self, key: Storage.settingsKey) ?? UserSettings()
        if environment.options.onboarded, !settings.onboarded {
            settings.onboarded = true
            environment.settingsStore.save(settings, key: Storage.settingsKey)
        }
        self.settings = settings
        engine = MorningEngine(state: environment.store.load() ?? EngineState(),
                               settings: settings.engineSettings(test: environment.options.test),
                               calendar: environment.calendar())
        if environment.options.debug {
            intentsReceived = environment.settingsStore.load(Int.self, key: Storage.intentsKey) ?? 0
        }
        demo = environment.options.show.flatMap { DemoScreen.make($0, settings: settings, now: environment.now(),
                                                                  calendar: environment.calendar()) }
    }

    var now: Date { environment.now() }

    // MARK: the single writer

    /// Applies one event. An event sent while another is being handled (an effect that answers at once)
    /// waits its turn, so effects always run in order and never interleave.
    func send(_ event: Event) {
        inbox.append(event)
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !inbox.isEmpty {
            let next = inbox.removeFirst()
            for effect in engine.handle(next) { perform(effect) }
            resumeSound()
        }
    }

    /// An alert button's intent ran. A background confirm waits for its cancels to reach AlarmKit before the
    /// intent returns, since iOS may suspend the app right after.
    func receiveAlertAction(_ ringID: UUID, _ action: AlertAction) async {
        if environment.options.debug {
            intentsReceived += 1
            environment.settingsStore.save(intentsReceived, key: Storage.intentsKey)
        }
        send(.alertAction(ringID: ringID, action, now: now))
        if action == .confirmAwake { await alarmCallsSettled() }
    }

    // MARK: settings

    func update(_ change: (inout UserSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        apply(next)
    }

    /// Saves the settings, then hands them to the engine.
    func apply(_ next: UserSettings) {
        settings = next
        environment.settingsStore.save(next, key: Storage.settingsKey)
        send(.settingsChanged(next.engineSettings(test: environment.options.test), now: now))
    }

    // MARK: permission

    /// Reads AlarmKit's permission (off the main thread) and applies it.
    func refreshAuthorization() async {
        applyAuthorization(await AlarmAuthorization.state())
    }

    func requestAlarms() async -> Bool {
        let state = await AlarmAuthorization.request()
        applyAuthorization(state)
        return state == .authorized
    }

    /// On each activation: ask for alarm permission once onboarding is done and iOS has not asked yet.
    func checkAuthorization() async {
        let state = await AlarmAuthorization.state()
        applyAuthorization(state)
        if settings.onboarded && state == .notDetermined {
            _ = await requestAlarms()
        }
    }

    func applyAuthorization(_ state: AlarmManager.AuthorizationState) {
        let authorized = state == .authorized
        let gained = authorized && alarmsAuthorized != true
        alarmsAuthorized = authorized
        // Schedules failed while alarms were off; read the table so reconcile retries them now.
        if gained, hasLaunched { perform(.readSystemTable) }
    }

    // MARK: what iOS reports

    /// AlarmKit's table changed. Sends `.alerting` when the set of alerting alarms is different.
    func alarmTableChanged(_ table: [SystemAlarm]) {
        systemTable = table
        let alerting = Set(table.filter(\.alerting).map(\.id))
        guard alerting != lastAlerting else { return }
        lastAlerting = alerting
        send(.alerting(alerting, now: now, audible: environment.audible(), coverVisible: coverVisible))
    }

    /// The full-screen cover finished presenting: takeover silencing may happen now (F5).
    func coverAppeared() {
        coverVisible = true
        send(.coverShown(now: now, audible: environment.audible()))
    }

    func coverDisappeared() {
        coverVisible = false
    }

    // MARK: effects

    /// Runs the engine's effects. AlarmKit schedule, cancel and table reads go through one serial queue, so a
    /// cancel never overtakes the schedules the engine put before it (Reconciler order: the deadline and guards
    /// first, cancels last). Silencing does not wait in that queue: it stops a ring that is alerting now.
    func perform(_ effect: Effect) {
        switch effect {
        case .persist:
            persist()
        case let .schedule(ring):
            enqueueAlarmCall { model in await model.schedule(ring) }
        case let .cancel(id):
            enqueueAlarmCall { model in await model.environment.alarms.cancel(id) }
        case .readSystemTable:
            enqueueAlarmCall { model in await model.readSystemTable() }
        case let .silence(id):
            guard takeoverIsCovered(id) else {
                modelLog.error("In-app sound is not playing: the system alarm keeps ringing")
                return
            }
            let alarms = environment.alarms
            Task { await alarms.stop(id) }
        case let .sound(command):
            play(command)
        case .dismissHomeSheets:
            sheetDismissals += 1
        case let .setIdleTimerDisabled(disabled):
            environment.setIdleTimerDisabled(disabled)
        case .disableAlarm:
            disableAlarm()
        }
    }

    /// Waits until every queued AlarmKit call, and every call those calls led to, has finished.
    func alarmCallsSettled() async {
        while let tail = alarmQueue {
            await tail.value
            if alarmQueue == tail { return }
        }
    }

    private func persist() {
        do {
            try environment.store.save(engine.state)
        } catch {
            modelLog.error("Engine state not saved: \(error.localizedDescription)")
        }
    }

    private func enqueueAlarmCall(_ work: @escaping @MainActor (AppModel) async -> Void) {
        if alarmCallsInFlight == 0 { environment.keepAlive(true) }
        alarmCallsInFlight += 1
        let previous = alarmQueue
        alarmQueue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
            alarmCallsInFlight -= 1
            if alarmCallsInFlight == 0 { environment.keepAlive(false) }
        }
    }

    private func schedule(_ ring: Ring) async {
        var ok = true
        do {
            try await environment.alarms.schedule(ring)
        } catch {
            ok = false
            modelLog.error("Schedule \(ring.kind.rawValue) at \(ring.date) failed: \(error.localizedDescription)")
        }
        send(.scheduled(ring.id, ok: ok, now: now))
    }

    private func readSystemTable() async {
        let table = await environment.alarms.table()
        systemTable = table
        send(.systemTable(table, now: now))
    }

    /// F3 takeover only silences the system alarm when the in-app sound really plays instead. A call, Siri or
    /// a failed audio session can stop it; then the system alarm keeps ringing. Other silences (a tapped
    /// button, an open challenge in use) never wait for the sound.
    private func takeoverIsCovered(_ id: UUID) -> Bool {
        guard engine.session.takenOver.contains(id) else { return true }
        resumeSound()
        return environment.sound.playing != nil
    }

    /// Starts the sound the engine asked for again if something stopped it (an audio interruption).
    func resumeSound() {
        guard case let .play(nudge) = engine.session.sound, environment.sound.playing == nil else { return }
        environment.sound.play(nudge: nudge)
        playing = environment.sound.playing
    }

    private func play(_ command: SoundCommand) {
        switch command {
        case let .play(nudge): environment.sound.play(nudge: nudge)
        case .stop: environment.sound.stop()
        }
        playing = environment.sound.playing
    }

    /// A finished one-off morning turned the alarm off (A4): save that, then tell the engine.
    private func disableAlarm() {
        var next = settings
        next.enabled = false
        apply(next)
    }
}
