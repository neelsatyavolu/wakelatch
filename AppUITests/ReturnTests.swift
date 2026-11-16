import XCTest

/// Leaving Wakelatch in the middle of a morning and opening it again from its icon. These run silently on
/// the simulator too; the same paths through the system alert's buttons are in AlertButtonTests (device).
final class ReturnTests: MorningUITestCase {
    /// U5 by the icon: a challenge left open at level 1 comes back at level 3 once the Deadline has passed,
    /// with a new problem, not the old one (C3).
    func testLeaveChallenge_reopenAfterDeadline_upgraded() {
        let ideal = launchMorning()
        startChallengeInApp(timeout: 40)
        XCTAssertEqual(debugState().level, 1)
        let oldProblem = problem.label
        XCUIDevice.shared.press(.home)
        // Compressed timing: the Deadline rings 120 s after Ideal.
        waitUntil(ideal.addingTimeInterval(123), "the Deadline to be due")
        let state = openFromIcon()
        XCTAssertEqual(state.screen, "challenge", "the open challenge should come back: \(state)")
        XCTAssertEqual(state.level, 3, "the open challenge must be upgraded to level 3: \(state)")
        XCTAssertEqual(state.challenge, "math")
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "challenge.problem not shown")
        XCTAssertNotEqual(problem.label, oldProblem, "the level-1 problem must not come back")
        XCTAssertTrue(problem.label.contains("×"), "level 3 is multiplication: \(problem.label)")
        XCTAssertEqual(app.staticTexts["challenge.headline"].label, "Problem 1 of 2")
        XCTAssertFalse(app.buttons["ringing.snooze"].exists, "Snooze must not be offered")
        solveMath()
    }

    /// U5 with a guard: a challenge left open is away while the first guard rings. Opened from the icon it is
    /// back at level 3, and the guard keeps ringing over it until the first answer (an idle challenge never
    /// silences, F4). Then nothing alerts under the cover.
    func testLeaveChallenge_guardRingsUntilFirstAnswer() {
        let ideal = launchMorning()
        startChallengeInApp(timeout: 40)
        XCTAssertEqual(debugState().level, 1)
        XCUIDevice.shared.press(.home)
        // Compressed timing: the first guard rings 145 s after Ideal.
        waitUntil(ideal.addingTimeInterval(150), "the first guard to ring")
        let state = openFromIcon()
        XCTAssertEqual(state.screen, "challenge", "the open challenge should come back: \(state)")
        XCTAssertEqual(state.level, 3, "the challenge must be at the guard's level: \(state)")
        waitForDebug("the guard ringing over the idle challenge", timeout: 5) { $0.alerting > 0 }
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "challenge.problem not shown")
        type(wrongAnswer(to: problem.label))
        waitForDebug("the first answer to silence the rings", timeout: 5) { $0.alerting == 0 }
        XCTAssertEqual(debugState().screen, "challenge")
        solveMath()
    }

    /// D1: after Snooze, opening the app again shows "Snoozed until h:mm" with only Start challenge, never home.
    func testSnoozeThenReopen_showsSnoozedUntil() {
        launchMorning()
        let snooze = app.buttons["ringing.snooze"]
        waitFor(snooze, "the main ring in the app", timeout: 40)
        snooze.tap()
        expectGone(snooze, timeout: 5, "the ringing screen after Snooze")
        XCTAssertEqual(debugState().screen, "none", "Snooze returns home for this visit")
        XCUIDevice.shared.press(.home)
        let state = openFromIcon()
        XCTAssertEqual(state.screen, "ringing", "opening after a snooze must show the morning: \(state)")
        XCTAssertEqual(state.sounding, false, "nothing rings between the snoozes: \(state)")
        XCTAssertNil(state.sound)
        let until = app.staticTexts["ringing.snoozedUntil"]
        waitFor(until, "Snoozed until", timeout: 5)
        XCTAssertTrue(until.label.hasPrefix("Snoozed until"), "label: \(until.label)")
        XCTAssertTrue(app.buttons["ringing.up"].exists, "Start challenge is offered")
        XCTAssertFalse(app.buttons["ringing.snooze"].exists, "no second Snooze while nothing rings")
        XCTAssertFalse(app.buttons["tomorrow.ideal"].isHittable, "home is showing during the morning")
        app.buttons["ringing.up"].tap()
        XCTAssertEqual(debugState().level, 1)
        solveMath()
    }
}
