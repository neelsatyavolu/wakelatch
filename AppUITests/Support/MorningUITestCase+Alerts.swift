import XCTest

/// The real AlarmKit alert, read and pressed through SpringBoard.
///
/// In the simulator the alert shows as a banner at the top (label "Wakelatch, <title>, <secondary>, Stop")
/// and stays expanded while it rings. Buttons are taken from inside the banner with that title, so a Stop of
/// another alert is never pressed by mistake.
extension MorningUITestCase {
    /// The ringing banner with `title`. Matches the banner element itself, not its children.
    func alert(_ title: String) -> XCUIElement {
        springboard.otherElements
            .matching(NSPredicate(format: "label BEGINSWITH 'Wakelatch, ' AND label CONTAINS %@", title)).firstMatch
    }

    /// Any Wakelatch alert banner.
    var anyAlert: XCUIElement {
        springboard.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Wakelatch, Wakelatch.'")).firstMatch
    }

    @discardableResult
    func waitForAlert(_ title: String, timeout: TimeInterval,
                      file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let banner = alert(title)
        XCTAssertTrue(banner.waitForExistence(timeout: timeout),
                      "system alert \"\(title)\" never showed within \(Int(timeout)) s", file: file, line: line)
        return banner
    }

    /// Waits for the alert `title`, checks it offers exactly `buttons`, and presses `press`.
    func pressAlert(_ title: String, _ press: String, expecting buttons: [String], timeout: TimeInterval,
                    file: StaticString = #filePath, line: UInt = #line) {
        let banner = waitForAlert(title, timeout: timeout, file: file, line: line)
        let labels = banner.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Set(labels), Set(buttons), "buttons on \"\(title)\"", file: file, line: line)
        let button = banner.buttons.matching(NSPredicate(format: "label == %@", press)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 2), "\(press) missing on \"\(title)\"", file: file, line: line)
        button.tap()
    }

    /// Presses Stop on an alert whose Stop only stops that ring (main, snooze, nudge), then checks the banner
    /// leaves and Wakelatch stays where it was.
    func pressPlainStop(_ title: String, expecting buttons: [String], timeout: TimeInterval,
                        file: StaticString = #filePath, line: UInt = #line) {
        pressAlert(title, "Stop", expecting: buttons, timeout: timeout, file: file, line: line)
        expectGone(alert(title), timeout: 10, "the stopped \"\(title)\" alert", file: file, line: line)
        // An intent that opens the app lands up to a couple of seconds after the banner leaves.
        XCTAssertFalse(app.wait(for: .runningForeground, timeout: 5), "Stop on \"\(title)\" must not open Wakelatch",
                       file: file, line: line)
    }

    // MARK: intents

    /// After an alert button whose intent opens Wakelatch: the app must come to the foreground on its own
    /// (never `activate()`, which hid the original defect). If it does not, the failure says whether the
    /// intent reached the app at all.
    func expectOpenedByIntent(intentsBefore: Int, file: StaticString = #filePath, line: UInt = #line) {
        if app.wait(for: .runningForeground, timeout: 15) { return }
        let state = openFromIcon(file: file, line: line)
        XCTFail("the alert button did not open Wakelatch; intents received: \(state.intents - intentsBefore), "
                + "state when opened by hand: \(state)", file: file, line: line)
    }

    /// Opens Wakelatch the way a person does, from its Home Screen icon, and returns its state.
    @discardableResult
    func openFromIcon(file: StaticString = #filePath, line: UInt = #line) -> DebugSnapshot {
        if app.state == .runningForeground { XCUIDevice.shared.press(.home) }
        let icon = springboard.icons["Wakelatch"]
        // A fresh install can land on a later Home Screen page: page right until the icon shows.
        var found = false
        for _ in 0..<4 {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: icon)
            if XCTWaiter().wait(for: [hittable], timeout: 3) == .completed {
                found = true
                break
            }
            springboard.swipeLeft()
        }
        XCTAssertTrue(found, "Wakelatch icon not on the Home Screen", file: file, line: line)
        icon.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Wakelatch did not open from its icon",
                      file: file, line: line)
        return debugState(file: file, line: line)
    }
}
