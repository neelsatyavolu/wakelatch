import XCTest

/// Captures each screen with sample data for design review and the App Store listing.
/// Writes PNGs to the folder in the WAKELATCH_SHOTS environment variable (simulator only).
@MainActor
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        try XCTSkipIf(ProcessInfo.processInfo.environment["WAKELATCH_SHOTS"] == nil, "screenshots only on request")
        addUIInterruptionMonitor(withDescription: "permission") { alert in
            guard alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap()
            return true
        }
    }

    func testCaptureScreens() {
        // WAKELATCH_SHOTS_SUFFIX (e.g. "-ax") captures only the two morning screens, for a large-text pass.
        if let suffix = ProcessInfo.processInfo.environment["WAKELATCH_SHOTS_SUFFIX"] {
            shoot("4-ringing\(suffix)", args: ["-uitest-onboarded", "-uitest-show=ringing"])
            shoot("5-challenge\(suffix)", args: ["-uitest-onboarded", "-uitest-show=challenge"])
            return
        }
        shoot("1-onboarding", args: ["-uitest-reset"])
        // Run after MorningFlowTests.testOnboardingReachesTomorrow so alarm permission is already granted.
        shoot("2-tomorrow", args: ["-uitest-reset", "-uitest-onboarded"])
        shoot("3-picker", args: ["-uitest-onboarded"]) {
            let row = self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'At the deadline'")).firstMatch
            if !row.isHittable { self.app.swipeUp() }
            row.tap()
            _ = self.app.buttons["challenge.math"].waitForExistence(timeout: 5)
        }
        shoot("4-ringing", args: ["-uitest-onboarded", "-uitest-show=ringing"])
        shoot("5-challenge", args: ["-uitest-onboarded", "-uitest-show=challenge"])
        shoot("6-released", args: ["-uitest-onboarded", "-uitest-show=released"]) { sleep(1) }
        shoot("7-night", args: ["-uitest-onboarded", "-uitest-show=night"])
    }

    private func shoot(_ name: String, args: [String], prepare: (() -> Void)? = nil) {
        app.terminate()
        // Simulated alarms: a real AlarmKit alarm set here would ring later, or crash SpringBoard with the
        // silent sound (see MorningUITestCase).
        app.launchArguments = ["-uitest-silent", "-uitest-simulated-alarms"] + args
        app.launch()
        sleep(2)
        prepare?()
        sleep(1)
        let dir = ProcessInfo.processInfo.environment["WAKELATCH_SHOTS"]!
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

}
