import XCTest

/// The in-app challenge: reading the problem, answering it, and the emergency skip.
extension MorningUITestCase {
    var problem: XCUIElement { app.staticTexts["challenge.problem"] }
    var released: XCUIElement { app.staticTexts["released.title"] }

    /// Solves every math problem until Released shows. Fails, never returns quietly, when no problem shows.
    func solveMath(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(problem.waitForExistence(timeout: 10), "challenge.problem never appeared", file: file, line: line)
        for _ in 0..<2 {
            let shown = problem.label
            type(answer(to: shown, file: file, line: line))
            if released.waitForExistence(timeout: 3) { return }
            // A level-3 challenge has a second problem; it must replace the first one.
            XCTAssertTrue(problem.exists, "neither Released nor a next problem after a right answer", file: file, line: line)
        }
        XCTAssertTrue(released.waitForExistence(timeout: 5), "Released never showed after solving", file: file, line: line)
    }

    /// Types into the answer field. Answers check themselves once they have as many digits as the answer.
    func type(_ number: Int) {
        let field = app.textFields["challenge.answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "challenge.answer missing")
        field.tap()
        field.typeText(String(number))
    }

    /// Parses "What is 12 + 30?" or "What is 17 × 6?".
    func answer(to label: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let body = label.replacingOccurrences(of: "What is ", with: "").replacingOccurrences(of: "?", with: "")
        let multiply = body.contains("×")
        let terms = body.components(separatedBy: multiply ? " × " : " + ").compactMap(Int.init)
        XCTAssertGreaterThanOrEqual(terms.count, 2, "could not parse the problem \"\(label)\"", file: file, line: line)
        return multiply ? terms.reduce(1, *) : terms.reduce(0, +)
    }

    /// A wrong answer with as many digits as the right one, so it is checked at once.
    func wrongAnswer(to label: String) -> Int {
        let right = answer(to: label)
        let up = right + 1
        return String(up).count == String(right).count ? up : right - 1
    }

    /// Opens the emergency skip sheet from the challenge and confirms it with the phrase.
    func skipMorning(file: StaticString = #filePath, line: UInt = #line) {
        let skip = app.buttons["challenge.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "challenge.skip missing", file: file, line: line)
        skip.tap()
        let text = app.descendants(matching: .any)["skip.text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "skip.text missing", file: file, line: line)
        text.tap()
        text.typeText("I need to skip this alarm")
        let confirm = app.buttons["skip.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "skip.confirm missing", file: file, line: line)
        XCTAssertTrue(confirm.isEnabled, "skip.confirm stayed disabled after the phrase", file: file, line: line)
        confirm.tap()
    }

    /// Bedside or the foreground cover: waits for the in-app ring and taps Start challenge.
    func startChallengeInApp(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let up = app.buttons["ringing.up"]
        XCTAssertTrue(up.waitForExistence(timeout: timeout), "in-app ring never showed", file: file, line: line)
        up.tap()
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "challenge.problem never appeared", file: file, line: line)
    }
}
