import XCTest

/// Onboarding to home, with the real AlarmKit permission prompt. The morning itself is covered by
/// AlertButtonTests (U1-U5, device only), InAppMorningTests (U6 device only, U7, U10, U11, U14),
/// AwakeCheckTests (U8, U9), RecoveryTests (U12, U13) and ReturnTests (U5 and D1 by the icon). On a device
/// they ring real AlarmKit alarms with a silent sound; on the simulator the alarms are simulated (see
/// MorningUITestCase).
final class MorningFlowTests: MorningUITestCase {
    func testOnboardingReachesTomorrow() {
        launch(["-uitest-reset"] + alarmArguments)
        let next = app.buttons["onboarding.next"]
        waitFor(next, "onboarding", timeout: 5)
        next.tap()                       // welcome
        next.tap()                       // allow alarms
        allowAlarmsIfAsked()
        waitFor(app.staticTexts["Before tomorrow"], "the tips step", timeout: 10)
        next.tap()                       // tips
        next.tap()                       // set alarm
        waitFor(app.buttons["tomorrow.ideal"], "home", timeout: 5)
        XCTAssertTrue(app.buttons["tomorrow.bedside"].exists)
        XCTAssertEqual(debugState().screen, "none")
    }
}
