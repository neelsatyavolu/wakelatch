import Foundation

/// The math challenge as a value: problems per level, auto-check, wrong-answer handling.
/// A new ring id (upgrade) means a new session.
public struct MathSession: Equatable, Sendable {
    /// What one input did.
    public enum Step: Equatable, Sendable {
        /// Not checked yet (shorter than the answer, or empty).
        case pending
        /// Wrong: a new problem at the same level, solved count kept, `misses` went up by one.
        case wrong
        /// Right, and more problems remain.
        case correct
        /// Right, and that was the last problem. Returned exactly once per session.
        case done
        /// Input after `done`. Nothing changes.
        case ignored
    }

    public let level: Int
    public private(set) var problem: MathChallenge
    public private(set) var answer: String
    public private(set) var solvedCount: Int
    /// Every wrong answer adds one, so the view can give feedback on each miss.
    public private(set) var misses: Int
    public private(set) var isDone: Bool

    public init(level: Int, using rng: inout some RandomNumberGenerator) {
        self.level = level
        self.problem = MathChallenge.make(level: level, using: &rng)
        self.answer = ""
        self.solvedCount = 0
        self.misses = 0
        self.isDone = false
    }

    /// Problems to solve: `ChallengeKind.math.goal(level:)` (1, 1, 2).
    public var goal: Int { ChallengeKind.math.goal(level: level) }

    /// "Problem 1 of 2" when the goal is above one, otherwise "Solve to stop".
    public var headline: String {
        goal > 1 ? "Problem \(min(solvedCount + 1, goal)) of \(goal)" : "Solve to stop"
    }

    /// Replaces the typed answer. Checks automatically once it has as many characters as the right answer.
    public mutating func enter(_ text: String, using rng: inout some RandomNumberGenerator) -> Step {
        guard !isDone else { return .ignored }
        answer = text
        return answer.count >= String(problem.answer).count ? check(using: &rng) : .pending
    }

    /// Checks the typed answer now (the Submit button). Empty input returns `.pending`.
    public mutating func submit(using rng: inout some RandomNumberGenerator) -> Step {
        guard !isDone else { return .ignored }
        guard !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return .pending }
        return check(using: &rng)
    }

    private mutating func check(using rng: inout some RandomNumberGenerator) -> Step {
        let right = problem.check(answer)
        answer = ""
        guard right else {
            misses += 1
            problem = MathChallenge.make(level: level, using: &rng)
            return .wrong
        }
        solvedCount += 1
        if solvedCount >= goal {
            isDone = true
            return .done
        }
        problem = MathChallenge.make(level: level, using: &rng)
        return .correct
    }
}
