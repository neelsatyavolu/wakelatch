import XCTest

/// End-to-end mornings against real AlarmKit in the simulator. `-uitest-soon` sets
/// Ideal to the next minute with a two-minute window, so each test waits a minute or two.
@MainActor
final class MorningFlowTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "permission") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    func testOnboardingReachesTomorrow() {
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()                       // welcome
        next.tap()                       // allow alarms
        allowIfAsked()
        XCTAssertTrue(app.staticTexts["Before tomorrow"].waitForExistence(timeout: 10))
        next.tap()                       // tips
        next.tap()                       // set alarm
        XCTAssertTrue(app.buttons["tomorrow.ideal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tomorrow.bedside"].exists)
    }

    /// App open (bedside): Wakelatch takes over with its own screen, then solve and awake checks.
    func testInAppRingSolveAndRelease() throws {
        launchSoon()
        app.buttons["tomorrow.bedside"].tap()
        let up = app.buttons["ringing.up"]
        XCTAssertTrue(up.waitForExistence(timeout: 150), "in-app ringing screen never appeared")
        XCTAssertFalse(springboard.buttons["Slide to stop"].exists)
        up.tap()
        try solveMath()
        XCTAssertTrue(app.staticTexts["released.title"].waitForExistence(timeout: 10))
        app.buttons["released.done"].tap()
        XCTAssertTrue(app.buttons["tomorrow.ideal"].waitForExistence(timeout: 10))
    }

    /// App in the background: the system alarm rings; "I'm up" opens the challenge.
    func testSystemAlarmOpensChallenge() throws {
        launchSoon()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(tapSystemButton(["I'm up", "Solve"], timeout: 200), "system alarm never showed I'm up or Solve")
        app.activate()
        for id in ["ringing.up", "ringing.solve"] where app.buttons[id].waitForExistence(timeout: 5) {
            app.buttons[id].tap()
            break
        }
        try solveMath()
        XCTAssertTrue(app.staticTexts["released.title"].waitForExistence(timeout: 10))
    }

    /// Snooze before the deadline: the screen goes away and the next ring comes back.
    func testSnoozeThenRingsAgain() throws {
        launchSoon()
        app.buttons["tomorrow.bedside"].tap()
        let snooze = app.buttons["ringing.snooze"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 150))
        snooze.tap()
        // The deadline ring (2 minutes after Ideal) can only be solved.
        XCTAssertTrue(app.buttons["ringing.solve"].waitForExistence(timeout: 150), "deadline ring never came")
        app.buttons["ringing.solve"].tap()
        try solveMath()
        XCTAssertTrue(app.staticTexts["released.title"].waitForExistence(timeout: 10))
    }

    // MARK: helpers

    private func launchSoon() {
        app.launchArguments = ["-uitest-reset", "-uitest-onboarded", "-uitest-soon"]
        app.launch()
        allowIfAsked()
        XCTAssertTrue(app.buttons["tomorrow.bedside"].waitForExistence(timeout: 10))
    }

    private func allowIfAsked() {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            for allow in [app.buttons["Allow"], springboard.buttons["Allow"]] where allow.exists {
                allow.tap()
                return
            }
            app.tap()   // lets the interruption monitor run
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func tapSystemButton(_ labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label].firstMatch
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func solveMath() throws {
        for _ in 0..<3 {
            let problem = app.staticTexts["challenge.problem"]
            guard problem.waitForExistence(timeout: 10) else { return }
            let field = app.textFields["challenge.answer"]
            field.tap()
            field.typeText(String(try answer(to: problem.label)))
            // Answers check themselves once they have enough digits; Submit is only a fallback.
            let submit = app.buttons["challenge.submit"]
            if submit.exists && submit.isEnabled { submit.tap() }
            if app.staticTexts["released.title"].waitForExistence(timeout: 2) { return }
        }
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
