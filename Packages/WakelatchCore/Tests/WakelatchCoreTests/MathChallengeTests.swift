import Testing
@testable import WakelatchCore

@Suite("MathChallenge")
struct MathChallengeTests {
    @Test("same seed gives the same problem")
    func deterministic() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect(MathChallenge.make(level: 2, using: &a) == MathChallenge.make(level: 2, using: &b))
    }

    @Test("answer matches the operands for every level", arguments: 1...3)
    func answerIsCorrect(level: Int) {
        var rng = SeededGenerator(seed: UInt64(level))
        for _ in 0..<200 {
            let p = MathChallenge.make(level: level, using: &rng)
            let expected = p.operands.dropFirst().reduce(p.operands[0]) { p.op == .add ? $0 + $1 : $0 * $1 }
            #expect(p.answer == expected)
        }
    }

    @Test("level 1 is two two-digit numbers added")
    func levelOne() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let p = MathChallenge.make(level: 1, using: &rng)
            #expect(p.op == .add)
            #expect(p.operands.count == 2)
            #expect(p.operands.allSatisfy { (10...99).contains($0) })
        }
    }

    @Test("level 3 is a two-digit times a one-digit number")
    func levelThree() {
        var rng = SeededGenerator(seed: 9)
        for _ in 0..<200 {
            let p = MathChallenge.make(level: 3, using: &rng)
            #expect(p.op == .multiply)
            #expect((11...99).contains(p.operands[0]))
            #expect((3...9).contains(p.operands[1]))
        }
    }

    @Test("checking accepts the answer with surrounding spaces, rejects others")
    func check() {
        let p = MathChallenge(operands: [12, 30], op: .add)
        #expect(p.check(" 42 "))
        #expect(!p.check("41"))
        #expect(!p.check(""))
        #expect(!p.check("forty-two"))
    }

    @Test("prompt reads like the sum")
    func prompt() {
        #expect(MathChallenge(operands: [12, 30, 5], op: .add).prompt == "12 + 30 + 5")
        #expect(MathChallenge(operands: [17, 6], op: .multiply).prompt == "17 × 6")
    }

    @Test("levels outside 1...3 are clamped")
    func clamped() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 1)
        #expect(MathChallenge.make(level: 0, using: &a) == MathChallenge.make(level: 1, using: &b))
    }
}
