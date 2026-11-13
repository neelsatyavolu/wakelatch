import Foundation
import Testing
@testable import WakelatchCore

@Suite("EyesOpenTracker")
struct EyesOpenTests {
    @Test("open eyes accumulate toward the goal")
    func accumulates() {
        var t = EyesOpenTracker(goal: 10)
        for i in 0...10 { t.update(time: Double(i), leftBlink: 0.1, rightBlink: 0.1) }
        #expect(t.isDone)
        #expect(t.progress == 1)
    }

    @Test("an ordinary blink doesn't reset progress")
    func blinkIsFine() {
        var t = EyesOpenTracker(goal: 10)
        t.update(time: 0, leftBlink: 0, rightBlink: 0)
        t.update(time: 4, leftBlink: 0, rightBlink: 0)
        t.update(time: 4.2, leftBlink: 0.9, rightBlink: 0.9)
        t.update(time: 4.4, leftBlink: 0.1, rightBlink: 0.1)
        #expect(t.openSeconds >= 4)
    }

    @Test("eyes closed for two seconds starts over")
    func longCloseResets() {
        var t = EyesOpenTracker(goal: 10)
        t.update(time: 0, leftBlink: 0, rightBlink: 0)
        t.update(time: 5, leftBlink: 0, rightBlink: 0)
        t.update(time: 5.1, leftBlink: 0.9, rightBlink: 0.9)
        t.update(time: 7.2, leftBlink: 0.9, rightBlink: 0.9)
        #expect(t.openSeconds == 0)
        #expect(!t.isDone)
    }

    @Test("losing the face pauses without resetting")
    func faceLost() {
        var t = EyesOpenTracker(goal: 10)
        t.update(time: 0, leftBlink: 0, rightBlink: 0)
        t.update(time: 3, leftBlink: 0, rightBlink: 0)
        t.faceLost()
        t.update(time: 20, leftBlink: 0, rightBlink: 0)
        #expect(t.openSeconds == 3)
    }
}

@Suite("ShakeCounter")
struct ShakeTests {
    @Test("a shake counts when force rises past the peak and settles")
    func counts() {
        var s = ShakeCounter(goal: 2)
        for g in [1.0, 2.6, 1.0, 1.1, 2.8, 0.9] { s.add(magnitude: g) }
        #expect(s.count == 2)
        #expect(s.isDone)
    }

    @Test("holding high force counts once")
    func hysteresis() {
        var s = ShakeCounter(goal: 5)
        for g in [2.6, 2.7, 2.9, 2.5] { s.add(magnitude: g) }
        #expect(s.count == 1)
    }

    @Test("gentle movement doesn't count")
    func gentle() {
        var s = ShakeCounter(goal: 5)
        for g in [1.0, 1.5, 1.9, 1.2] { s.add(magnitude: g) }
        #expect(s.count == 0)
    }
}

@Suite("PhraseChallenge")
struct PhraseTests {
    @Test("matches ignoring case, extra spaces and trailing punctuation spaces")
    func tolerant() {
        let p = PhraseChallenge(phrase: "The kettle is on and the day has started.")
        #expect(p.check("the kettle is on and  the day has started. "))
        #expect(p.check("The kettle is on and the day has started."))
        #expect(!p.check("The kettle is on"))
    }

    @Test("smart quotes and apostrophes match plain ones")
    func quotes() {
        let p = PhraseChallenge(phrase: "I'm up and I'm staying up.")
        #expect(p.check("I’m up and I’m staying up."))
    }

    @Test("phrases get longer with level")
    func levels() {
        var rng = SeededGenerator(seed: 3)
        let short = PhraseChallenge.make(level: 1, using: &rng).phrase
        let long = PhraseChallenge.make(level: 3, using: &rng).phrase
        #expect(long.count > short.count)
    }
}

@Suite("SkipLedger")
struct SkipTests {
    var calendar = Calendar(identifier: .gregorian)

    func date(_ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: 7))!
    }

    @Test("two skips a month")
    func twoPerMonth() {
        var l = SkipLedger()
        #expect(l.remaining(at: date(11, 1), calendar: calendar) == 2)
        let first = l.use(at: date(11, 2), calendar: calendar)
        let second = l.use(at: date(11, 9), calendar: calendar)
        let third = l.use(at: date(11, 20), calendar: calendar)
        #expect(first && second && !third)
        #expect(l.remaining(at: date(11, 20), calendar: calendar) == 0)
    }

    @Test("a new month restores them")
    func newMonth() {
        var l = SkipLedger()
        _ = l.use(at: date(11, 2), calendar: calendar)
        _ = l.use(at: date(11, 3), calendar: calendar)
        #expect(l.remaining(at: date(12, 1), calendar: calendar) == 2)
    }

    @Test("the skip phrase must be typed exactly, case-insensitive")
    func phrase() {
        #expect(SkipLedger.phraseMatches(SkipLedger.phrase.uppercased()))
        #expect(!SkipLedger.phraseMatches("skip"))
    }
}

@Suite("AwakeChecks")
struct AwakeCheckTests {
    @Test("checks at +5 and +12 minutes, each with three guard rings a minute apart")
    func plan() {
        let solved = Date(timeIntervalSince1970: 1_800_000_000)
        let checks = AwakeChecks.plan(solvedAt: solved)
        #expect(checks.count == 2)
        #expect(checks[0] == [300, 360, 420, 480].map { solved.addingTimeInterval($0) })
        #expect(checks[1].first == solved.addingTimeInterval(720))
    }
}

@Suite("Challenge kinds")
struct ChallengeKindTests {
    @Test("difficulty word per level")
    func difficulty() {
        #expect(ChallengeKind.math.summary(level: 1) == "Two numbers to add")
        #expect(ChallengeKind.steps.goal(level: 3) > ChallengeKind.steps.goal(level: 1))
        #expect(ChallengeKind.eyesOpen.goal(level: 2) == 30)
    }

    @Test("every kind has a name and symbol")
    func names() {
        for kind in ChallengeKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.symbol.isEmpty)
        }
    }
}
