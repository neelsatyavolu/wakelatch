import Foundation
import WakelatchCore

/// Everything the user chooses. Stored as JSON in UserDefaults.
struct UserSettings: Codable, Equatable {
    var times = WakeTimes(ideal: ClockTime(hour: 6, minute: 40), deadline: ClockTime(hour: 7, minute: 10))
    var enabled = true
    /// Calendar weekdays (1 = Sunday). Empty means only the next morning.
    var repeatDays: Set<Int> = Set(1...7)
    var plan = PlanOptions()
    var snoozeChallenge: ChallengeKind = .math
    var deadlineChallenge: ChallengeKind = .math
    var awakeChecks = true
    var bedsideKeepsScreenOn = true
    var onboarded = false

    /// The settings as the engine takes them, with any UI-test timing and pinned morning applied.
    func engineSettings(test: TestOptions?) -> EngineSettings {
        let production = PlanTiming.production(plan)
        return EngineSettings(times: times, repeatDays: repeatDays, enabled: enabled,
                              timing: test?.timing(production: production) ?? production,
                              snoozeChallenge: snoozeChallenge, deadlineChallenge: deadlineChallenge,
                              awakeChecks: test?.awakeChecks ?? awakeChecks, keepScreenOn: bedsideKeepsScreenOn,
                              pinnedMorning: test?.pinnedIdeal)
    }
}

/// JSON-in-UserDefaults storage for settings and UI-test options.
struct Storage {
    static let settingsKey = "settings"
    /// UI tests only: how many alert-button intents reached the app (`DebugState.intents`).
    static let intentsKey = "uitestIntents"
    /// Keys written by builds before the morning engine. Read once by `LegacyMigration`, then removed.
    static let legacyKeys = ["rings", "records", "skips", "acknowledged"]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    func remove(_ keys: [String]) {
        for key in keys { defaults.removeObject(forKey: key) }
    }

    func removeAll() {
        remove([Self.settingsKey, TestOptions.storageKey, Self.intentsKey] + Self.legacyKeys)
    }
}
