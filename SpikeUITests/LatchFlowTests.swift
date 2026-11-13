import XCTest

/// End-to-end latch flow against real AlarmKit in the simulator:
/// arm a chain, wait for the system alarm, open the challenge from the
/// alarm's button, solve it, and check the rest of the chain is cancelled.
@MainActor
final class LatchFlowTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-uitest-reset"]
        app.launch()
    }

    func testArmRingSolveReleases() throws {
        // Defaults: first ring in 1 min, guard rings every 60 s.
        addUIInterruptionMonitor(withDescription: "alarm permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.buttons["home.arm"].tap()
        allowAlarmsIfAsked()
        XCTAssertTrue(app.staticTexts["home.status"].waitForExistence(timeout: 10))
        let armed = app.staticTexts["home.status"]
        XCTAssertTrue(wait(for: armed, labelHasPrefix: "Latched.", timeout: 15), "status: \(armed.label)")

        // Background the app so the alarm shows as a system alert.
        XCUIDevice.shared.press(.home)
        let opened = openChallengeFromAlarm(timeout: 90)
        XCTAssertTrue(opened, "no alarm alert with Solve/Stop appeared")

        app.activate()
        let problem = app.staticTexts["challenge.problem"]
        if !problem.waitForExistence(timeout: 20) {
            dumpAppLog()
            XCTFail("challenge screen did not open")
        }
        XCTAssertTrue(app.staticTexts["challenge.headline"].label.hasPrefix("Ring 1 of"))

        // A wrong answer keeps the latch.
        typeAnswer("1")
        XCTAssertTrue(app.staticTexts["Not it. New problem."].waitForExistence(timeout: 5))

        typeAnswer(String(try answer(to: problem.label)))
        let status = app.staticTexts["home.status"]
        XCTAssertTrue(wait(for: status, labelHasPrefix: "Nothing armed.", timeout: 15), "status: \(status.label)")
    }

    /// Stop without solving: the next guard ring must still sound.
    func testStopWithoutSolvingRingsAgain() throws {
        app.buttons["home.arm"].tap()
        allowAlarmsIfAsked()
        XCTAssertTrue(wait(for: app.staticTexts["home.status"], labelHasPrefix: "Latched.", timeout: 15))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(tapAlarmButton("Stop", timeout: 90), "first ring never showed Stop")

        // Walk away from the challenge.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(tapAlarmButton("Solve", timeout: 90), "no guard ring after Stop")

        app.activate()
        let problem = app.staticTexts["challenge.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["challenge.headline"].label.hasPrefix("Ring"))
        typeAnswer(String(try answer(to: problem.label)))
        XCTAssertTrue(wait(for: app.staticTexts["home.status"], labelHasPrefix: "Nothing armed.", timeout: 15))
    }

    // MARK: helpers

    private func tapAlarmButton(_ label: String, timeout: TimeInterval) -> Bool {
        let button = springboard.buttons[label].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists && button.isHittable {
                button.tap()
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func allowAlarmsIfAsked() {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            for allow in [app.buttons["Allow"], springboard.buttons["Allow"]] where allow.exists {
                allow.tap()
                return
            }
            if app.staticTexts["home.status"].label.hasPrefix("Latched.") { return }
            app.navigationBars.firstMatch.tap()  // any interaction lets the interruption monitor run
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Taps Solve (or Stop) on the ringing alarm, wherever the system shows it.
    private func openChallengeFromAlarm(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in ["Solve", "Stop"] {
                let button = springboard.buttons[label].firstMatch
                if button.exists && button.isHittable {
                    print("DIAG tapped alarm button: \(label)")
                    button.tap()
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func dumpAppLog() {
        print("DIAG-SCREEN\n" + app.debugDescription)
        app.buttons["Log"].firstMatch.tap()
        for line in app.staticTexts.allElementsBoundByIndex.prefix(15) { print("DIAG-LOG \(line.label)") }
    }

    private func typeAnswer(_ text: String) {
        let field = app.textFields["challenge.answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["challenge.submit"].tap()
    }

    private func wait(for element: XCUIElement, labelHasPrefix prefix: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    /// Parses "What is 12 + 30 + 5?" or "What is 17 × 6?".
    private func answer(to label: String) throws -> Int {
        let body = label.replacingOccurrences(of: "What is ", with: "").replacingOccurrences(of: "?", with: "")
        if body.contains("×") {
            return body.components(separatedBy: " × ").compactMap { Int($0) }.reduce(1, *)
        }
        let terms = body.components(separatedBy: " + ").compactMap { Int($0) }
        XCTAssertFalse(terms.isEmpty, "could not parse \(label)")
        return terms.reduce(0, +)
    }
}
