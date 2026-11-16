import XCTest

/// U1-U5: the buttons on the real system alarm, pressed through SpringBoard with Wakelatch killed or in the
/// background. A button whose intent opens Wakelatch must land straight on the challenge, with no Snooze.
/// These need a real alarm to ring, so they run on a device only (`requireSystemAlarms()`); the simulator
/// covers the in-app side in InAppMorningTests and ReturnTests.
final class AlertButtonTests: MorningUITestCase {
    /// The I'm up path the owner hit with the app killed: one tap, and the challenge is on screen.
    func testImUp_cold_opensChallengeDirectly() throws {
        try requireSystemAlarms()
        launchMorning()
        let before = debugState().intents
        app.terminate()
        pressAlert(AlertTitle.snooze, "I'm up", expecting: ["I'm up", "Stop"], timeout: 90)
        expectOpenedByIntent(intentsBefore: before)
        expectChallengeLandedDirectly(level: 1)
        solveMath()
    }

    /// The same with the app suspended: cold and warm must give the same screen (S8).
    func testImUp_suspended_opensChallengeDirectly() throws {
        try requireSystemAlarms()
        launchMorning()
        let before = debugState().intents
        XCUIDevice.shared.press(.home)
        pressAlert(AlertTitle.snooze, "I'm up", expecting: ["I'm up", "Stop"], timeout: 90)
        expectOpenedByIntent(intentsBefore: before)
        expectChallengeLandedDirectly(level: 1)
        solveMath()
    }

    /// Stop before the Deadline is the system snooze: the app stays shut and the next ring comes.
    func testMainStop_isSnooze_nextRingComes() throws {
        try requireSystemAlarms()
        launchMorning()
        let before = debugState().intents
        XCUIDevice.shared.press(.home)
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 90)
        pressAlert(AlertTitle.snooze, "I'm up", expecting: ["I'm up", "Stop"], timeout: 70)
        expectOpenedByIntent(intentsBefore: before)
        let state = expectChallengeLandedDirectly(level: 1)
        XCTAssertEqual(state.kind, "snooze", "the challenge belongs to the snooze ring that was answered")
        solveMath()
    }

    /// Stop on the Deadline alert opens the level-3 challenge, cold.
    func testDeadlineStop_cold_opensL3Challenge() throws {
        try requireSystemAlarms()
        launchMorning()
        let before = debugState().intents
        app.terminate()
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 90)
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 70)
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 70)
        pressAlert(AlertTitle.deadline, "Stop", expecting: ["Solve", "Stop"], timeout: 70)
        expectOpenedByIntent(intentsBefore: before)
        expectChallengeLandedDirectly(level: 3)
        XCTAssertTrue(problem.label.contains("×"), "level 3 is multiplication: \(problem.label)")
        XCTAssertEqual(app.staticTexts["challenge.headline"].label, "Problem 1 of 2")
        solveMath()
    }

    /// A challenge left open at L1 comes back at L3 when a guard's Solve is pressed, not the old problem.
    /// The Deadline's own Stop opens the app first; leaving again lets the first guard ring (U5).
    func testLeaveChallenge_guardReturnsUpgraded() throws {
        try requireSystemAlarms()
        launchMorning()
        app.buttons["tomorrow.bedside"].tap()
        startChallengeInApp(timeout: 40)
        XCTAssertEqual(debugState().level, 1)
        let oldProblem = problem.label
        let before = debugState().intents
        XCUIDevice.shared.press(.home)
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 70)
        pressPlainStop(AlertTitle.snooze, expecting: ["I'm up", "Stop"], timeout: 70)
        pressAlert(AlertTitle.deadline, "Stop", expecting: ["Solve", "Stop"], timeout: 70)
        expectOpenedByIntent(intentsBefore: before)
        let beforeGuard = expectChallengeLandedDirectly(level: 3).intents
        XCUIDevice.shared.press(.home)
        // Guards share the Deadline's alert; the first one rings 25 s after it.
        pressAlert(AlertTitle.deadline, "Solve", expecting: ["Solve", "Stop"], timeout: 40)
        expectOpenedByIntent(intentsBefore: beforeGuard)
        let state = expectChallengeLandedDirectly(level: 3)
        XCTAssertEqual(state.challenge, "math")
        XCTAssertNotEqual(problem.label, oldProblem, "the level-1 problem must not come back")
        solveMath()
    }

    // MARK: helpers

    /// The challenge is on screen at `level` within 5 s, with no ringing screen or Snooze in between.
    @discardableResult
    func expectChallengeLandedDirectly(level: Int, file: StaticString = #filePath,
                                       line: UInt = #line) -> DebugSnapshot {
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "challenge.problem not shown within 5 s", file: file, line: line)
        XCTAssertFalse(app.buttons["ringing.snooze"].exists, "Snooze must not be offered", file: file, line: line)
        let state = debugState(file: file, line: line)
        XCTAssertEqual(state.screen, "challenge", file: file, line: line)
        XCTAssertEqual(state.level, level, "challenge level", file: file, line: line)
        return state
    }
}
