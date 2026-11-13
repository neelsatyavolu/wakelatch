import Foundation

public enum ChallengeKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case math, phrase, eyesOpen, steps, shake

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .math: "Math"
        case .phrase: "Type a sentence"
        case .eyesOpen: "Eyes open"
        case .steps: "Walk"
        case .shake: "Shake"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .math: "plus.forwardslash.minus"
        case .phrase: "keyboard"
        case .eyesOpen: "eye"
        case .steps: "figure.walk"
        case .shake: "iphone.radiowaves.left.and.right"
        }
    }

    /// Steps, seconds, shakes or problems, depending on the kind.
    public func goal(level: Int) -> Int {
        let l = min(max(level, 1), 3) - 1
        switch self {
        case .math: return [1, 1, 2][l]
        case .phrase: return 1
        case .eyesOpen: return [20, 30, 45][l]
        case .steps: return [20, 40, 60][l]
        case .shake: return [15, 25, 35][l]
        }
    }

    public func summary(level: Int) -> String {
        let l = min(max(level, 1), 3)
        switch self {
        case .math: return ["Two numbers to add", "Three numbers to add", "Two problems, one multiplication"][l - 1]
        case .phrase: return ["A short sentence", "A longer sentence", "A long sentence"][l - 1]
        case .eyesOpen: return "Keep your eyes open for \(goal(level: l)) seconds"
        case .steps: return "Walk \(goal(level: l)) steps"
        case .shake: return "Shake the phone \(goal(level: l)) times"
        }
    }
}

/// Eyes must stay open (blink weight below the threshold) for `goal` seconds.
/// Ordinary blinks are fine; eyes closed for `resetAfter` seconds start over.
public struct EyesOpenTracker: Sendable {
    public let goal: Double
    public let closedThreshold: Double = 0.6
    public let resetAfter: Double = 2

    public private(set) var openSeconds: Double = 0
    private var lastTime: Double?
    private var closedSince: Double?

    public init(goal: Double) {
        self.goal = goal
    }

    public var progress: Double { min(openSeconds / goal, 1) }
    public var isDone: Bool { openSeconds >= goal }

    public mutating func update(time: Double, leftBlink: Double, rightBlink: Double) {
        defer { lastTime = time }
        let closed = leftBlink > closedThreshold && rightBlink > closedThreshold
        if closed {
            closedSince = closedSince ?? time
            if let since = closedSince, time - since >= resetAfter { openSeconds = 0 }
            return
        }
        closedSince = nil
        if let last = lastTime, !isDone { openSeconds = min(goal, openSeconds + (time - last)) }
    }

    /// The camera lost the face: pause until it's back, without counting the gap.
    public mutating func faceLost() {
        lastTime = nil
        closedSince = nil
    }
}

/// Counts shakes from acceleration magnitude (in g) with hysteresis.
public struct ShakeCounter: Sendable {
    public let goal: Int
    let peak = 2.3
    let settle = 1.4
    public private(set) var count = 0
    private var armed = true

    public init(goal: Int) {
        self.goal = goal
    }

    public var isDone: Bool { count >= goal }

    public mutating func add(magnitude: Double) {
        if armed && magnitude >= peak {
            count += 1
            armed = false
        } else if !armed && magnitude <= settle {
            armed = true
        }
    }
}

/// Type a sentence. Case, repeated spaces, trailing spaces and curly quotes don't matter.
public struct PhraseChallenge: Equatable, Sendable {
    public let phrase: String

    public init(phrase: String) {
        self.phrase = phrase
    }

    public func check(_ input: String) -> Bool {
        Self.normalize(input) == Self.normalize(phrase)
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static let phrases: [[String]] = [
        ["I'm up and I'm staying up.", "Feet on the floor, eyes open.", "Good morning. Time to move."],
        ["The kettle is on and the day has started.", "Sleep can wait until tonight, not now.",
         "I set this alarm for a reason and I'm keeping it."],
        ["Every minute I stay up now is a minute I don't have to rush later.",
         "The hardest part of the morning is this sentence, and it's almost over.",
         "I am awake, I am standing up, and I am not going back to bed."],
    ]

    public static func make(level: Int, using rng: inout some RandomNumberGenerator) -> PhraseChallenge {
        let set = phrases[min(max(level, 1), 3) - 1]
        return PhraseChallenge(phrase: set.randomElement(using: &rng) ?? set[0])
    }
}

/// Emergency skips: two a month, each by typing a phrase.
public struct SkipLedger: Codable, Hashable, Sendable {
    public static let perMonth = 2
    public static let phrase = "I need to skip this alarm"

    public private(set) var used: [Date] = []

    public init() {}

    public func remaining(at date: Date, calendar: Calendar) -> Int {
        let month = calendar.dateComponents([.year, .month], from: date)
        let usedThisMonth = used.filter { calendar.dateComponents([.year, .month], from: $0) == month }.count
        return max(0, Self.perMonth - usedThisMonth)
    }

    /// Records a skip if one is left. Returns false when none remain.
    public mutating func use(at date: Date, calendar: Calendar) -> Bool {
        guard remaining(at: date, calendar: calendar) > 0 else { return false }
        used.append(date)
        return true
    }

    public static func phraseMatches(_ input: String) -> Bool {
        PhraseChallenge(phrase: phrase).check(input)
    }
}
