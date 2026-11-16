import Foundation
import Synchronization
import Testing
@testable import Wakelatch
import WakelatchCore

/// The AlarmKit stand-in the simulator UI tests use (`-uitest-simulated-alarms`). It must behave like the
/// one-shot AlarmKit alarms Wakelatch schedules, or the in-app UI tests would prove nothing.
struct SimulatedAlarmsTests {
    private let start = Date(timeIntervalSince1970: 1_767_600_000)
    private let clock: Clock
    private let url: URL

    init() {
        clock = Clock(start)
        url = FileManager.default.temporaryDirectory.appending(path: "simulated-\(UUID().uuidString).json")
    }

    private func make() -> SimulatedAlarms {
        let clock = clock
        return SimulatedAlarms(url: url, now: { clock.now })
    }

    private func ring(_ kind: RingKind, at seconds: TimeInterval) -> Ring {
        Ring(date: start.addingTimeInterval(seconds), kind: kind, level: 1, morning: start, challenge: .math)
    }

    @Test func alertsFromItsDateUntilStopped() async throws {
        let alarms = make()
        let main = ring(.main, at: 60)
        let snooze = ring(.snooze, at: 100)
        try await alarms.schedule(main)
        try await alarms.schedule(snooze)
        #expect(await alarms.table().map(\.alerting) == [false, false])
        #expect(await alarms.table().map(\.ring) == [main, snooze])

        clock.now = start.addingTimeInterval(60)
        #expect(await alarms.table().filter(\.alerting).map(\.id) == [main.id])

        // Stop before its date keeps a later ring; stop while alerting ends it.
        await alarms.stop(snooze.id)
        await alarms.stop(main.id)
        #expect(await alarms.table().map(\.id) == [snooze.id])
    }

    @Test func cancelRemovesAndScheduleReplaces() async throws {
        let alarms = make()
        let main = ring(.main, at: 60)
        try await alarms.schedule(main)
        try await alarms.schedule(main)
        #expect(await alarms.table().count == 1)
        await alarms.cancel(main.id)
        #expect(await alarms.table().isEmpty)
    }

    /// Like AlarmKit's table, it outlives the process: a kill and relaunch reads the same alarms.
    @Test func tableSurvivesARelaunch() async throws {
        let main = ring(.main, at: 60)
        try await make().schedule(main)
        let relaunched = make()
        #expect(await relaunched.table().map(\.ring) == [main])
    }

    @Test func updatesReportAnAlarmStartingToAlert() async throws {
        let alarms = make()
        let main = ring(.main, at: 1)
        try await alarms.schedule(main)
        var updates = alarms.alarmUpdates().makeAsyncIterator()
        #expect(await updates.next()?.map(\.alerting) == [false])
        clock.now = start.addingTimeInterval(1)
        #expect(await updates.next()?.map(\.alerting) == [true])
        await alarms.stop(main.id)
        #expect(await updates.next()?.isEmpty == true)
    }

    @Test func flagIsSavedForLaunchesWithoutArguments() {
        let options = LaunchOptions.parse(["-uitest-simulated-alarms"], now: start, saved: nil)
        #expect(options.test?.simulatedAlarms == true)
        #expect(options.silent)
        #expect(LaunchOptions.parse([], now: start, saved: options.test).test?.simulatedAlarms == true)
    }

    /// Options saved by an older build, without the newer fields, still decode, so the profile and its
    /// silence are not lost when iOS starts the app without arguments.
    @Test func olderSavedOptionsStillDecode() throws {
        let older = Data(#"{"nudges":false,"forceAudible":true}"#.utf8)
        let options = try JSONDecoder().decode(TestOptions.self, from: older)
        #expect(options == TestOptions(nudges: false, forceAudible: true))
    }
}

/// A clock the test moves by hand.
private final class Clock: Sendable {
    private let value: Mutex<Date>

    init(_ start: Date) {
        value = Mutex(start)
    }

    var now: Date {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
