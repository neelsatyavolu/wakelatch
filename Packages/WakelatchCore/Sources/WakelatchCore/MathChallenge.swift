import Foundation

/// An arithmetic problem the user types the answer to.
public struct MathChallenge: Equatable, Sendable {
    public enum Op: Equatable, Sendable {
        case add, multiply
    }

    public let operands: [Int]
    public let op: Op

    public init(operands: [Int], op: Op) {
        precondition(!operands.isEmpty, "a problem needs at least one operand")
        self.operands = operands
        self.op = op
    }

    public var answer: Int {
        switch op {
        case .add: operands.reduce(0, +)
        case .multiply: operands.reduce(1, *)
        }
    }

    public var prompt: String {
        let symbol = op == .add ? " + " : " × "
        return operands.map(String.init).joined(separator: symbol)
    }

    public func check(_ input: String) -> Bool {
        Int(input.trimmingCharacters(in: .whitespaces)) == answer
    }

    /// Level 1: two 2-digit numbers added. Level 2: three 2-digit numbers added.
    /// Level 3: a 2-digit number times a 1-digit number. Other levels are clamped.
    public static func make(level: Int, using rng: inout some RandomNumberGenerator) -> MathChallenge {
        switch min(max(level, 1), 3) {
        case 1:
            return MathChallenge(operands: (0..<2).map { _ in Int.random(in: 10...99, using: &rng) }, op: .add)
        case 2:
            return MathChallenge(operands: (0..<3).map { _ in Int.random(in: 10...99, using: &rng) }, op: .add)
        default:
            return MathChallenge(
                operands: [Int.random(in: 11...99, using: &rng), Int.random(in: 3...9, using: &rng)],
                op: .multiply
            )
        }
    }
}

/// Deterministic generator (SplitMix64) so problems are reproducible in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
