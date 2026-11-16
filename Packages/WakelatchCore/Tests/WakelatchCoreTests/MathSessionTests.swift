import Foundation
import Testing
import WakelatchCore

/// Contract M1-M6 (scenarios M01-M07): the math challenge as a value.
@Suite("M: MathSession")
struct MathSessionTests {
    func session(level: Int, seed: UInt64 = 7) -> (MathSession, SeededGenerator) {
        var rng = SeededGenerator(seed: seed)
        let session = MathSession(level: level, using: &rng)
        return (session, rng)
    }

    /// A wrong answer with as many characters as the right one.
    func wrong(for answer: Int) -> String {
        let up = String(answer + 1)
        return up.count == String(answer).count ? up : String(answer - 1)
    }

    @Test("M01: input shorter than the answer is stored and returns pending")
    func pendingBelowLength() {
        var (s, rng) = session(level: 2)
        let answer = String(s.problem.answer)
        let partial = String(answer.dropLast())
        #expect(s.enter(partial, using: &rng) == .pending)
        #expect(s.answer == partial)
        #expect(s.solvedCount == 0)
        #expect(s.misses == 0)
    }

    @Test("M02: input reaching the answer's length is checked automatically")
    func autoCheckAtLength() {
        var (s, rng) = session(level: 1)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .done)
        #expect(s.isDone)
        #expect(s.solvedCount == 1)
    }

    @Test("M03: a wrong answer makes a new problem at the same level and keeps the solved count")
    func wrongKeepsCount() {
        var (s, rng) = session(level: 3)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .correct)
        #expect(s.solvedCount == 1)
        #expect(s.answer == "")
        #expect(s.enter(wrong(for: s.problem.answer), using: &rng) == .wrong)
        #expect(s.solvedCount == 1)
        #expect(s.misses == 1)
        #expect(s.answer == "")
        #expect(s.problem.op == .multiply)
        #expect(!s.isDone)
    }

    @Test("M04: levels 1 and 2 need one problem", arguments: [1, 2])
    func oneProblem(level: Int) {
        var (s, rng) = session(level: level)
        #expect(s.goal == 1)
        #expect(s.headline == "Solve to stop")
        #expect(s.problem.op == .add)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .done)
    }

    @Test("M05: level 3 is two multiplication problems, and the summary says every problem multiplies")
    func levelThree() {
        var (s, rng) = session(level: 3)
        #expect(s.goal == 2)
        #expect(s.headline == "Problem 1 of 2")
        #expect(s.problem.op == .multiply)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .correct)
        #expect(s.headline == "Problem 2 of 2")
        #expect(s.problem.op == .multiply)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .done)
        let summary = ChallengeKind.math.summary(level: 3).lowercased()
        #expect(summary.contains("multipl"))
        #expect(!summary.contains("one multiplication"))
        #expect(!summary.contains("add"))
    }

    @Test("M06: done is returned exactly once; later input is ignored and changes nothing")
    func doneOnce() {
        var (s, rng) = session(level: 1)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .done)
        let frozen = s
        #expect(s.enter("12", using: &rng) == .ignored)
        #expect(s.enter(String(s.problem.answer), using: &rng) == .ignored)
        #expect(s.submit(using: &rng) == .ignored)
        #expect(s == frozen)
    }

    @Test("M07: every miss increments the miss counter, not only the first")
    func everyMissCounts() {
        var (s, rng) = session(level: 2)
        for expected in 1...3 {
            #expect(s.enter(wrong(for: s.problem.answer), using: &rng) == .wrong)
            #expect(s.misses == expected)
        }
        #expect(s.solvedCount == 0)
    }

    @Test("M2: submit with empty input is pending; submit with a short wrong answer is a miss")
    func submit() {
        var (s, rng) = session(level: 2)
        #expect(s.submit(using: &rng) == .pending)
        #expect(s.misses == 0)
        _ = s.enter("1", using: &rng)
        #expect(s.submit(using: &rng) == .wrong)
        #expect(s.misses == 1)
        #expect(s.answer == "")
    }

    @Test("M2: submit with the right answer solves")
    func submitRight() {
        var (s, rng) = session(level: 1, seed: 99)
        let answer = String(s.problem.answer)
        #expect(s.enter(String(answer.dropLast()), using: &rng) == .pending)
        _ = s.enter(answer, using: &rng)
        #expect(s.isDone)
    }

    @Test("M1: the session level is kept and the goal matches ChallengeKind.math.goal", arguments: 1...3)
    func goalMatches(level: Int) {
        let (s, _) = session(level: level)
        #expect(s.level == level)
        #expect(s.goal == ChallengeKind.math.goal(level: level))
    }
}
