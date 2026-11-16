import XCTest

/// U6, U7, U10, U11, U14: the morning while Wakelatch is open, and the nudge from the lock screen side.
final class InAppMorningTests: MorningUITestCase {
    /// A nudge stops with one tap on its system alert and changes nothing else: every latched ring stays with
    /// AlarmKit. Device only (`requireSystemAlarms()`); U7 covers the in-app nudge on the simulator.
    func testNudge_oneTap_morningContinues() throws {
        try requireSystemAlarms()
        launchMorning(ideal: 55, nudges: true)
        let before = debugState()
        XCTAssertEqual(before.count("nudge"), 2)
        XCUIDevice.shared.press(.home)
        pressPlainStop(AlertTitle.nudge, expecting: ["Stop"], timeout: 30)
        let after = openFromIcon()
        XCTAssertEqual(after.screen, "none", "a nudge stopped on its alert must not come back on screen: \(after)")
        XCTAssertTrue(app.buttons["tomorrow.ideal"].isHittable, "home is not showing")
        for kind in ["main", "snooze", "deadline", "guardRing"] {
            XCTAssertEqual(after.count(kind), before.count(kind), "\(kind) alarms after the nudge Stop")
        }
        XCUIDevice.shared.press(.home)
        // The second nudge is stopped the same way; then the main ring still comes.
        pressPlainStop(AlertTitle.nudge, expecting: ["Stop"], timeout: 30)
        waitForAlert(AlertTitle.snooze, timeout: 40)
    }

    /// Bedside: every ring of the morning is handled in the app, and no system alert sits over the cover.
    func testBedside_fullMorningInApp() {
        launchMorning(ideal: 55, nudges: true, extra: ["-uitest-force-audible"])
        app.buttons["tomorrow.bedside"].tap()
        let stop = app.buttons["ringing.stop"]
        waitFor(stop, "the in-app nudge", timeout: 30)
        expectNoSystemAlertOverCover()
        // The nudge screen stays until tapped (contract S5), it does not time out on its own.
        expectStays(stop, for: 10, "the nudge screen")
        XCTAssertEqual(debugState().sound, "nudge", "the nudge screen should play the softer sound")
        stop.tap()
        snoozeInApp(expectedKinds: ["main"])
        snoozeInApp(expectedKinds: ["snooze"])
        snoozeInApp(expectedKinds: ["snooze"])
        let solve = app.buttons["ringing.solve"]
        waitFor(solve, "the in-app Deadline ring", timeout: 60)
        expectNoSystemAlertOverCover()
        XCTAssertFalse(app.buttons["ringing.snooze"].exists, "no Snooze after the Deadline")
        solve.tap()
        let state = debugState()
        XCTAssertEqual(state.level, 3)
        XCTAssertNil(state.sound, "the chime goes quiet for the challenge")
        solveMath()
    }

    /// A sheet open on home when the ring fires is closed, and the ring takes the screen (F6).
    func testSheetOpen_ringTakesOver() {
        launchMorning()
        app.buttons["tomorrow.settings"].tap()
        waitFor(app.buttons["settings.done"], "the Settings sheet", timeout: 5)
        waitFor(app.buttons["ringing.up"], "the ring over the Settings sheet", timeout: 60)
        XCTAssertFalse(app.buttons["settings.done"].exists, "the Settings sheet is still open")

        app.terminate()
        launchMorning()
        app.buttons["tomorrow.ideal"].tap()
        waitFor(app.buttons["time.done"], "the time sheet", timeout: 5)
        waitFor(app.buttons["ringing.up"], "the ring over the time sheet", timeout: 60)
        XCTAssertFalse(app.buttons["time.done"].exists, "the time sheet is still open")
    }

    /// The emergency skip ends the morning: nothing more rings and one skip is used.
    func testSkip_endsMorning() {
        launchMorning()
        let launched = Date()
        startChallengeInApp(timeout: 60)
        XCTAssertEqual(debugState().skipsLeft, 2)
        skipMorning()
        let state = waitForDebug("the skipped morning's alarms to leave AlarmKit", timeout: 15) { $0.scheduled == 0 }
        XCTAssertEqual(state.screen, "none")
        XCTAssertEqual(state.skipsLeft, 1, "one skip used")
        // The last guard would have rung 25 + 195 s after launch; watch a little past it.
        let rest = max(10, launched.addingTimeInterval(235).timeIntervalSinceNow)
        expectDebugStays("home with no alarm after the skip", for: rest) {
            $0.screen == "none" && $0.scheduled == 0 && $0.alerting == 0
        }
        XCTAssertFalse(anyAlert.exists, "a system alert after the skip")
    }

    /// A wrong answer of the right length gives a new problem, an empty answer field and never releases.
    /// Several misses in a row: a digit left in the field after a miss (seen in a full run) garbles the next
    /// answer into another miss.
    func testWrongAnswer_newProblem_notReleased() {
        launchMorning()
        startChallengeInApp(timeout: 60)
        for _ in 0..<4 {
            let shown = problem.label
            type(wrongAnswer(to: shown))
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", shown), object: problem)
            XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "the problem did not change")
            expectAnswerFieldEmpty()
            XCTAssertFalse(released.exists, "a wrong answer released the alarm")
            XCTAssertTrue(app.staticTexts["challenge.feedback"].label.contains("Not it"), "no feedback for the miss")
        }
        XCTAssertEqual(debugState().screen, "challenge")
        solveMath()
    }

    private func expectAnswerFieldEmpty(file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["challenge.answer"]
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '' OR value == 'Answer'"),
                                              object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [empty], timeout: 2), .completed,
                       "the answer field kept \(String(describing: field.value)) after a miss", file: file, line: line)
    }

    // MARK: helpers

    /// Waits for the next in-app ring of `expectedKinds`, checks the cover owns it, and snoozes in-app.
    private func snoozeInApp(expectedKinds: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        let snooze = app.buttons["ringing.snooze"]
        waitFor(snooze, "in-app Snooze for \(expectedKinds)", timeout: 60, file: file, line: line)
        let state = debugState(file: file, line: line)
        XCTAssertTrue(expectedKinds.contains(state.kind ?? ""), "ring on screen: \(state)", file: file, line: line)
        XCTAssertEqual(state.sounding, true, file: file, line: line)
        XCTAssertEqual(state.sound, "chime", "the ringing screen should play the chime", file: file, line: line)
        expectNoSystemAlertOverCover(file: file, line: line)
        snooze.tap()
        expectGone(snooze, timeout: 5, "the ringing screen after Snooze", file: file, line: line)
        XCTAssertNil(debugState(file: file, line: line).sound, "the chime kept going after Snooze",
                     file: file, line: line)
    }

    /// With the volume treated as audible, the app silences the system alarm when its cover shows (F3), so
    /// no alarm keeps alerting under it and no SpringBoard alert stays over it.
    private func expectNoSystemAlertOverCover(file: StaticString = #filePath, line: UInt = #line) {
        waitForDebug("the app to silence the alarm under its cover", timeout: 3, file: file, line: line) {
            $0.alerting == 0
        }
        expectDebugStays("no alarm alerting under the cover", for: 3, file: file, line: line) { $0.alerting == 0 }
        XCTAssertFalse(anyAlert.exists, "a system alert over the cover", file: file, line: line)
    }
}
