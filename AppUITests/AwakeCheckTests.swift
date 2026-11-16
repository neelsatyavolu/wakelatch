import XCTest

/// U8, U9: the awake checks after a solve.
final class AwakeCheckTests: MorningUITestCase {
    /// Six awake-check alarms (two checks, each with two guards) are held right after the solve and stay there
    /// once the solve's reconcile has run (fix 1).
    func testSolve_awakeChecksSurviveTheSync() {
        launchMorning()
        startChallengeInApp(timeout: 60)
        solveMath()
        expectSixAwakeChecks()
    }

    /// U8 on a device: "I'm up" on the system "Still up?" alert confirms the check in the background, and its
    /// guards never ring.
    func testAwakeCheckImUp_confirmsInBackground() throws {
        try requireSystemAlarms()
        launchMorning()
        startChallengeInApp(timeout: 60)
        solveMath()
        expectSixAwakeChecks()
        let before = debugState().intents
        app.buttons["released.done"].tap()
        XCUIDevice.shared.press(.home)
        pressAlert(AlertTitle.awake, "I'm up", expecting: ["I'm up", "Stop"], timeout: 45)
        XCTAssertFalse(app.wait(for: .runningForeground, timeout: 5), "the background confirm opened Wakelatch")
        // Confirmed: the alert leaves, and the check's guard (20 s later) never rings.
        expectGone(alert(AlertTitle.awake), timeout: 10, "the confirmed awake check alert")
        expectAbsent(alert(AlertTitle.awake), for: 30, "the confirmed check's guard")
        let state = openFromIcon()
        XCTAssertEqual(state.intents, before + 1, "the confirm intent should have reached Wakelatch once")
        XCTAssertEqual(state.count("awakeCheck"), 3, "only the second check and its guards stay: \(state)")
    }

    /// Released left open: the awake check takes the screen when it is due, without Done (fix 9). "I'm up"
    /// in the app confirms it, and the check's guards leave the alarms.
    func testReleasedLeftOpen_checkTakesOver() {
        launchMorning()
        startChallengeInApp(timeout: 60)
        solveMath()
        let up = app.buttons["awake.up"]
        waitFor(up, "the awake check over Released", timeout: 45)
        XCTAssertFalse(released.exists, "Released stayed over the awake check")
        XCTAssertEqual(debugState().screen, "awakeCheck")
        up.tap()
        let state = waitForDebug("the first check and its guards to leave the alarms", timeout: 10) {
            $0.count("awakeCheck") == 3
        }
        XCTAssertEqual(state.alerting, 0, "the confirmed check is still alerting: \(state)")
        expectAbsent(up, for: 25, "the confirmed check's guard")
    }

    private func expectSixAwakeChecks(file: StaticString = #filePath, line: UInt = #line) {
        waitForDebug("the six awake checks to be scheduled", timeout: 10, file: file, line: line) {
            $0.count("awakeCheck") == 6
        }
        expectDebugStays("the awake checks after the reconcile settles", for: 6, file: file, line: line) {
            $0.count("awakeCheck") == 6 && $0.scheduled == 6
        }
    }
}
