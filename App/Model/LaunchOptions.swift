import Foundation
import WakelatchCore

/// UI-test settings that outlive one launch. A UI test kills the app and taps an alarm button, and iOS then
/// starts the app without the test's launch arguments, so these are saved and reused until `-uitest-reset`.
struct TestOptions: Codable, Equatable {
    static let storageKey = "uitestOptions"

    /// Replaces the production timing. Nil keeps production.
    var timing: PlanTiming?
    /// The single morning's Ideal (engine `pinnedMorning`). Nil keeps the user's times.
    var pinnedIdeal: Date?
    var nudges = true
    /// Overrides the user's awake-check setting when set.
    var awakeChecks: Bool?
    /// Delay before each AlarmKit schedule call, to test a kill in the middle of a pass.
    var slowScheduleMilliseconds: Int?
    /// Treat the media volume as loud enough, so takeover silencing happens in the simulator.
    var forceAudible = false
    /// Use `SimulatedAlarms` instead of AlarmKit: the simulator cannot ring a real alarm without a sound.
    var simulatedAlarms = false

    /// The timing the engine uses: this profile (or `production`), with nudges removed when they are off.
    func timing(production: PlanTiming) -> PlanTiming {
        var result = timing ?? production
        if !nudges { result.nudgeOffsets = [] }
        return result
    }
}

extension TestOptions {
    /// Tolerates options saved by an older build that lack newer fields. A profile that failed to decode
    /// would drop the test profile, and with it the silence, for a launch iOS makes without arguments.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timing = try values.decodeIfPresent(PlanTiming.self, forKey: .timing)
        pinnedIdeal = try values.decodeIfPresent(Date.self, forKey: .pinnedIdeal)
        nudges = try values.decodeIfPresent(Bool.self, forKey: .nudges) ?? true
        awakeChecks = try values.decodeIfPresent(Bool.self, forKey: .awakeChecks)
        slowScheduleMilliseconds = try values.decodeIfPresent(Int.self, forKey: .slowScheduleMilliseconds)
        forceAudible = try values.decodeIfPresent(Bool.self, forKey: .forceAudible) ?? false
        simulatedAlarms = try values.decodeIfPresent(Bool.self, forKey: .simulatedAlarms) ?? false
    }
}

/// What the launch arguments ask for. Flags take a value either as `-flag value` or `-flag=value`:
/// - `-uitest-reset`: clear settings, morning state and the alarm ledger.
/// - `-uitest-onboarded`: skip onboarding.
/// - `-uitest-timing compressed|production`: the timing profile.
/// - `-uitest-ideal <seconds>`: one morning with its Ideal this many seconds after launch.
/// - `-uitest-nudges 0|1`, `-uitest-awake 0|1`: switch nudges or awake checks off or on.
/// - `-uitest-soon`: shorthand for compressed timing, no nudges, Ideal in 60 s.
/// - `-uitest-slow-schedule [ms]`: wait this long (300 ms by default) before each AlarmKit schedule.
/// - `-uitest-force-audible`: treat the volume as loud enough for takeover.
/// - `-uitest-simulated-alarms`: keep alarms in `SimulatedAlarms` instead of AlarmKit (simulator UI tests).
/// - `-uitest-show=<screen>`: screenshot mode with a sample screen.
/// - `-uitest-silent`: no sound at all. Every `-uitest` flag implies it, and so does the unit-test host.
///
/// Any `-uitest` flag starts (and saves) a test profile, so a later launch without arguments, such as iOS
/// starting the app for an alert button, stays silent and keeps the debug probe. Only debug builds (the
/// ones UI tests run) read a saved profile back: a TestFlight or App Store build installed over a phone
/// that once ran UI tests must never stay silent or pinned to a test morning.
struct LaunchOptions: Equatable {
    var reset = false
    var onboarded = false
    var show: String?
    var test: TestOptions?
    /// Show the hidden `debug.state` element.
    var debug = false
    /// Nothing may make a sound: the in-app player only records what it would play, and AlarmKit alarms use
    /// the bundled silent sound instead of the system alarm tone.
    var silent = false

    /// How often the foreground loop sends `.tick`: every second under UI tests, every 5 s otherwise.
    var tickInterval: Duration { debug ? .seconds(1) : .seconds(5) }

    static let production = LaunchOptions()

    /// The saved profile a launch may use: none in a release build.
    static func savedProfile(_ saved: TestOptions?, debugBuild: Bool = isDebugBuild) -> TestOptions? {
        debugBuild ? saved : nil
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// - Parameter unitTestHost: the process hosts the WakelatchTests unit tests, which are always silent.
    static func parse(_ args: [String], now: Date, saved: TestOptions?, unitTestHost: Bool = false) -> LaunchOptions {
        let flags = Flags(args)
        let reset = flags.has("-uitest-reset")
        let start = reset ? nil : saved
        let test = flags.anyUITestFlag ? flags.apply(to: start ?? TestOptions(), now: now) : start
        return LaunchOptions(reset: reset, onboarded: flags.has("-uitest-onboarded"),
                             show: flags.value("-uitest-show"), test: test,
                             debug: test != nil, silent: test != nil || unitTestHost)
    }
}

/// Reads `-flag`, `-flag value` and `-flag=value` arguments.
private struct Flags {
    let args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    /// Any `-uitest` flag at all, including `-uitest-onboarded`, `-uitest-show` and `-uitest-silent`.
    var anyUITestFlag: Bool { args.contains { $0.hasPrefix("-uitest") } }

    func has(_ flag: String) -> Bool {
        args.contains { $0 == flag || $0.hasPrefix(flag + "=") }
    }

    func value(_ flag: String) -> String? {
        if let joined = args.first(where: { $0.hasPrefix(flag + "=") }) {
            return String(joined.dropFirst(flag.count + 1))
        }
        guard let index = args.firstIndex(of: flag), index + 1 < args.count,
              !args[index + 1].hasPrefix("-") else { return nil }
        return args[index + 1]
    }

    func apply(to base: TestOptions, now: Date) -> TestOptions {
        var options = base
        if has("-uitest-soon") {
            options.timing = .compressed
            options.nudges = false
            options.pinnedIdeal = now.addingTimeInterval(60)
        }
        switch value("-uitest-timing") {
        case "compressed": options.timing = .compressed
        case "production": options.timing = nil
        default: break
        }
        if let seconds = value("-uitest-ideal").flatMap(TimeInterval.init) {
            options.pinnedIdeal = now.addingTimeInterval(seconds)
        }
        if let nudges = value("-uitest-nudges") { options.nudges = nudges != "0" }
        if let awake = value("-uitest-awake") { options.awakeChecks = awake != "0" }
        if has("-uitest-slow-schedule") {
            options.slowScheduleMilliseconds = value("-uitest-slow-schedule").flatMap(Int.init) ?? 300
        }
        if has("-uitest-force-audible") { options.forceAudible = true }
        if has("-uitest-simulated-alarms") { options.simulatedAlarms = true }
        return options
    }
}
