import XCTest

/// U12, U13: a relaunch in the middle of a morning, and a kill in the middle of scheduling.
final class RecoveryTests: MorningUITestCase {
    /// Killed while the main ring is going off, then opened again with no morning flags: the first screen is
    /// already the morning, still sounding, never home.
    func testRelaunchMidMorning_landsOnMorning() {
        let ideal = launchMorning()
        XCUIDevice.shared.press(.home)
        if Self.simulatedAlarms {
            // The app's own Ideal, so the main ring is really due before the kill.
            waitUntil(ideal.addingTimeInterval(3), "the main ring to be due")
        } else {
            waitForAlert(AlertTitle.snooze, timeout: 60)
        }
        app.terminate()
        launch(["-uitest-onboarded"] + alarmArguments, answerPrompt: false)
        let first = debugState(timeout: 3)
        XCTAssertEqual(first.screen, "ringing", "the first screen after the relaunch must be the morning: \(first)")
        XCTAssertEqual(first.kind, "main")
        let state = waitForDebug("the main ring sounding", timeout: 5) { $0.screen == "ringing" && $0.sounding == true }
        XCTAssertEqual(state.kind, "main")
        waitFor(app.buttons["ringing.up"], "the morning's ring after a relaunch", timeout: 5)
        XCTAssertFalse(app.buttons["tomorrow.ideal"].isHittable, "home is showing during the morning")
    }

    /// Killed 1.5 s into a pass that schedules one alarm a second: the next launch completes the chain.
    func testKillMidSync_chainRestored() {
        launch(["-uitest-reset", "-uitest-onboarded", "-uitest-timing", "compressed", "-uitest-ideal", "120",
                "-uitest-nudges", "0", "-uitest-slow-schedule", "1000"] + alarmArguments)
        // A fixed delay is the point of this test: the kill must land in the middle of the pass.
        Thread.sleep(forTimeInterval: 1.5)
        let partial = debugState()
        XCTAssertLessThan(partial.scheduled, 7, "the pass finished before the kill; the test proves nothing")
        app.terminate()
        launch(["-uitest-onboarded"] + alarmArguments)
        let full = ["main": 1, "snooze": 2, "deadline": 1, "guardRing": 3]
        waitForDebug("the full chain after the relaunch", timeout: 20) { $0.byKind == full }
        // No stray or duplicate alarm arrives once the relaunch's pass has settled.
        expectDebugStays("exactly the chain", for: 3) { $0.byKind == full && $0.scheduled == 7 }
    }
}
