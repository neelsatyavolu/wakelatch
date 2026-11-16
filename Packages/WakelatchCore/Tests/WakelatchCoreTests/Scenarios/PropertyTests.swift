import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Group P: seeded random runs. P01 checks INV1-INV10 after every step (and R1, R7 on every step) for 2000 seeds of
/// 40-120 actions; P02 checks that a cold launch and a warm resume from the same history show the same thing.
/// Seeds are fixed: a failure names its seed and the last actions, so it can be replayed as a named test.
@Suite("P: property tests")
struct PropertyTests {
    static let batches = 20
    static let seedsPerBatch = 100

    @Test("P01: random event sequences keep every invariant, persist first and re-read after target changes",
          arguments: 0..<batches)
    func p01(batch: Int) {
        var failures = 0
        for offset in 0..<Self.seedsPerBatch where failures < 3 {
            let seed = UInt64(batch * Self.seedsPerBatch + offset)
            if let problem = Self.run(seed: seed) {
                failures += 1
                Issue.record("P01 seed \(seed): \(problem)")
            }
        }
    }

    /// Runs one seed; returns a description of the first problem, or nil.
    static func run(seed: UInt64) -> String? {
        var driver = FuzzDriver(seed: seed)
        var sim = driver.makeSim()
        let steps = driver.int(40...120)
        for _ in 0..<steps {
            driver.step(&sim)
            if sim.checker.violationCount > 0 { break }
        }
        let tail = driver.trace.suffix(12).joined(separator: " | ")
        if let first = sim.violations.first {
            return "\(first) after: \(tail)"
        }
        let complete = sim.steps.filter { !$0.truncated }
        if let step = complete.first(where: { $0.stateChanged && $0.effects.first != .persist }) {
            return "R7: \(step.event) changed state but its first effect is \(String(describing: step.effects.first)) after: \(tail)"
        }
        if let step = complete.first(where: { $0.targetChanged && !$0.isSystemTable && !$0.effects.contains(.readSystemTable) }) {
            return "R1: \(step.event) changed target without readSystemTable after: \(tail)"
        }
        return nil
    }

    @Test("P02 (S8): from the same random history, a cold launch and a warm resume show the same screen and sound",
          arguments: 0..<6)
    func p02(batch: Int) {
        var failures = 0
        for offset in 0..<50 where failures < 3 {
            let seed = UInt64(100_000 + batch * 50 + offset)
            if let problem = Self.coldWarm(seed: seed) {
                failures += 1
                Issue.record("P02 seed \(seed): \(problem)")
            }
        }
    }

    static func coldWarm(seed: UInt64) -> String? {
        var driver = FuzzDriver(seed: seed)
        var sim = driver.makeSim()
        for _ in 0..<driver.int(10...60) { driver.step(&sim) }
        sim.faults = SimFaults()
        if !sim.isForeground { sim.open() }
        sim.settle()
        sim.suspend()
        sim.advance(by: TimeInterval(driver.int(0...600)))
        var cold = sim
        cold.kill()
        cold.open()
        var warm = sim
        warm.open()
        let tail = driver.trace.suffix(8).joined(separator: " | ")
        if cold.screen != warm.screen { return "screen cold \(cold.screen) warm \(warm.screen) after: \(tail)" }
        if cold.sound != warm.sound { return "sound cold \(cold.sound) warm \(warm.sound) after: \(tail)" }
        if let first = cold.violations.first ?? warm.violations.first { return "\(first) after: \(tail)" }
        return nil
    }

    @Test("P01: the same seed replays the same run")
    func deterministic() {
        var a = FuzzDriver(seed: 42)
        var b = FuzzDriver(seed: 42)
        var simA = a.makeSim()
        var simB = b.makeSim()
        for _ in 0..<40 {
            a.step(&simA)
            b.step(&simB)
        }
        #expect(a.trace == b.trace)
        #expect(simA.eventLog == simB.eventLog)
        #expect(simA.state == simB.state)
    }
}

extension SimRecord {
    /// A reconcile pass answers the table it was given; adopting from it needs no second read (R1).
    var isSystemTable: Bool {
        if case .systemTable = event { return true }
        return false
    }
}
