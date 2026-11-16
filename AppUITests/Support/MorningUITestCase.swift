import XCTest

/// Base for the morning UI tests (plan section 3). Every morning runs on compressed timing:
/// with Ideal at I, snoozes ring at I+40 s (L1) and I+80 s (L2), the deadline at I+120 s, guards at I+145,
/// I+170 and I+195 s, and awake checks at solve+30 s and solve+70 s, each followed by 2 guards 20 s apart.
///
/// Helpers assert. A missing screen or alert fails the test where it happens; nothing is skipped quietly.
///
/// Silence (owner request): every launch passes `-uitest-silent`, so the in-app chime never plays. On a device
/// AlarmKit alarms ring with a bundled silent file. The iOS 26.5 simulator cannot do that: any custom alarm
/// sound, the silent file included, crashes SpringBoard's tone player when the alarm fires, and the only
/// other sound is the audible system tone. So on the simulator:
/// - in-app tests keep their alarms in the app's `SimulatedAlarms` (`-uitest-simulated-alarms`), which alert
///   on time like AlarmKit's but have no system alert and make no sound;
/// - tests that press buttons on the real system alert call `requireSystemAlarms()`, which skips them with
///   that reason. They run on a device.
@MainActor
class MorningUITestCase: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    enum AlertTitle {
        static let nudge = "Wakelatch. Ideal time soon."
        static let snooze = "Wakelatch. Stop to snooze."
        static let deadline = "Wakelatch. Deadline. Solve to stop."
        static let awake = "Wakelatch. Still up?"
    }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        // A morning left ringing would alert into the next test.
        app.terminate()
    }

    // MARK: launching

    /// True on the simulator, where alarms are kept by `SimulatedAlarms` (see the type comment).
    static var simulatedAlarms: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static let systemAlarmsUnavailable = """
        Needs a real AlarmKit alert, which the iOS 26.5 simulator cannot ring silently: a custom sound (the \
        bundled silent file) crashes SpringBoard's tone player (TLAlertQueuePlayerController) when the alarm \
        fires, and the system sound is audible. The owner asked for silent test runs. Run on a device, where \
        the silent file works.
        """

    /// Call first in a test that presses the real system alert. On the simulator it skips the test, saying why.
    func requireSystemAlarms() throws {
        if Self.simulatedAlarms { throw XCTSkip(Self.systemAlarmsUnavailable) }
    }

    /// The launch arguments that keep alarms silent on this destination (empty on a device).
    var alarmArguments: [String] { Self.simulatedAlarms ? ["-uitest-simulated-alarms"] : [] }

    /// A fresh install state with one pinned morning `ideal` seconds from now on compressed timing.
    /// Returns the morning's Ideal as the app set it from its own clock at launch.
    @discardableResult
    func launchMorning(ideal: Int = 25, nudges: Bool = false, extra: [String] = []) -> Date {
        let roughly = Date().addingTimeInterval(TimeInterval(ideal))
        launch(["-uitest-reset", "-uitest-onboarded", "-uitest-timing", "compressed",
                "-uitest-ideal", String(ideal), "-uitest-nudges", nudges ? "1" : "0"] + alarmArguments + extra)
        let state = debugState()
        XCTAssertEqual(state.screen, "none", "a fresh morning should start on home")
        let held = waitForDebug("the alarms to hold the morning", timeout: 15) { $0.byKind["deadline"] == 1 }
        XCTAssertNotNil(held.firstMorning, "debug.state has no morning: \(held)")
        return held.firstMorning.map { Date(timeIntervalSince1970: $0) } ?? roughly
    }

    /// - Parameter answerPrompt: wait up to 3 s for the AlarmKit permission prompt after launching. A test
    ///   that checks the very first screen passes false.
    func launch(_ arguments: [String], answerPrompt: Bool = true) {
        // Silent: no alarm or chime may be heard while tests run (owner request). Every -uitest flag implies
        // it; it is named here too so the intent is plain.
        app.launchArguments = ["-uitest-silent"] + arguments
        app.launch()
        if answerPrompt { allowAlarmsIfAsked() }
    }

    /// AlarmKit permission has no `simctl privacy` service, so the first launch after an install answers the
    /// system prompt here. Later launches see no prompt.
    func allowAlarmsIfAsked() {
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    // MARK: debug.state

    var debugElement: XCUIElement { app.descendants(matching: .any)["debug.state"].firstMatch }

    func debugState(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> DebugSnapshot {
        guard debugElement.waitForExistence(timeout: timeout) else {
            XCTFail("debug.state never appeared", file: file, line: line)
            return .empty
        }
        guard let snapshot = DebugSnapshot.decode(debugElement.value) else {
            XCTFail("debug.state did not decode: \(String(describing: debugElement.value))", file: file, line: line)
            return .empty
        }
        return snapshot
    }

    /// Waits until the decoded debug state satisfies `condition`, then returns it.
    @discardableResult
    func waitForDebug(_ what: String, timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line,
                      _ condition: @escaping (DebugSnapshot) -> Bool) -> DebugSnapshot {
        XCTAssertTrue(debugElement.waitForExistence(timeout: 10), "debug.state never appeared", file: file, line: line)
        let element = debugElement
        let predicate = NSPredicate { _, _ in
            MainActor.assumeIsolated { DebugSnapshot.decode(element.value).map(condition) ?? false }
        }
        let met = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                                   timeout: timeout) == .completed
        let last = DebugSnapshot.decode(element.value)
        XCTAssertTrue(met, "timed out after \(Int(timeout)) s waiting for \(what); last state \(String(describing: last))",
                      file: file, line: line)
        return last ?? .empty
    }

    // MARK: in-app elements

    func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval,
                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(what) never appeared within \(Int(timeout)) s",
                      file: file, line: line)
    }

    /// Asserts `element` does not appear for `seconds` (an inverted expectation, not a sleep).
    func expectAbsent(_ element: XCUIElement, for seconds: TimeInterval, _ what: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
        appears.isInverted = true
        let result = XCTWaiter().wait(for: [appears], timeout: seconds)
        XCTAssertEqual(result, .completed, "\(what) appeared", file: file, line: line)
    }

    /// Asserts `element` stays on screen for `seconds`.
    func expectStays(_ element: XCUIElement, for seconds: TimeInterval, _ what: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "\(what) is not on screen", file: file, line: line)
        let leaves = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        leaves.isInverted = true
        XCTAssertEqual(XCTWaiter().wait(for: [leaves], timeout: seconds), .completed,
                       "\(what) went away within \(Int(seconds)) s", file: file, line: line)
    }

    /// Asserts the debug state keeps satisfying `condition` for `seconds`.
    func expectDebugStays(_ what: String, for seconds: TimeInterval, file: StaticString = #filePath,
                          line: UInt = #line, _ condition: @escaping (DebugSnapshot) -> Bool) {
        let element = debugElement
        let broken = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { DebugSnapshot.decode(element.value).map { !condition($0) } ?? true }
        }, object: nil)
        broken.isInverted = true
        XCTAssertEqual(XCTWaiter().wait(for: [broken], timeout: seconds), .completed,
                       "\(what) did not hold: \(String(describing: DebugSnapshot.decode(element.value)))",
                       file: file, line: line)
    }

    /// Waits for the clock to pass `date`: a ring that is due while the app is away has to be waited for.
    func waitUntil(_ date: Date, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= date }, object: nil)
        let timeout = max(1, date.timeIntervalSinceNow + 5)
        XCTAssertEqual(XCTWaiter().wait(for: [passed], timeout: timeout), .completed, "waiting for \(what)",
                       file: file, line: line)
    }

    func expectGone(_ element: XCUIElement, timeout: TimeInterval, _ what: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed,
                       "\(what) was still there after \(Int(timeout)) s", file: file, line: line)
    }
}

/// The decoded value of the app's hidden `debug.state` element (`DebugState` in the app).
struct DebugSnapshot: Decodable, Equatable {
    var screen = "unknown"
    var kind: String?
    var level: Int?
    var sounding: Bool?
    var challenge: String?
    /// Ideal of the ring's morning on screen, seconds since 1970.
    var morning: Double?
    /// Ideal of the earliest morning the app holds, seconds since 1970.
    var firstMorning: Double?
    var acknowledged = 0
    var scheduled = 0
    var byKind: [String: Int] = [:]
    /// System (or simulated) alarms alerting now.
    var alerting = 0
    var intents = 0
    var skipsLeft = 0
    /// The in-app sound that would be playing ("chime" or "nudge"); nothing is heard under UI tests.
    var sound: String?

    static let empty = DebugSnapshot()

    static func decode(_ value: Any?) -> DebugSnapshot? {
        guard let text = value as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DebugSnapshot.self, from: data)
    }

    func count(_ kind: String) -> Int { byKind[kind] ?? 0 }
}
