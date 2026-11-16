import Foundation
import Testing
import WakelatchCore
import WakelatchCoreTestSupport

/// Regressions for the engine defects found in review: one test per finding, driving the engine directly.
@Suite("Review: engine regressions")
struct ReviewEngineTests {
    static let threeHours = SimFixture.standard {
        $0.times = WakeTimes(ideal: ClockTime(hour: 5, minute: 0), deadline: ClockTime(hour: 8, minute: 0))
        $0.timing = .production(PlanOptions(snoozeMinutes: 3))
    }

    func table(_ rings: [Ring]) -> [SystemAlarm] {
        rings.map { SystemAlarm(id: $0.id, fireDate: $0.date, ring: $0, alerting: false) }
    }

    func guards(_ engine: MorningEngine, day: Int) -> Int {
        engine.state.target.filter { $0.kind == .guardRing && $0.morning == Std.t(5, 0, day: day) }.count
    }

    /// A level-1 snooze of today dated 5 min 25 s after the Deadline, left over from a longer window.
    let stale = Ring(date: Std.t(7, 15, 25), kind: .snooze, level: 1, morning: Std.today, challenge: .math)

    @Test("Review 1 (R2, C6): a stale L1 snooze after the Deadline is not adopted; the pass cancels it")
    func staleSnoozeNotAdopted() {
        var engine = MorningEngine(state: EngineState(target: Std.morning()), settings: SimFixture.standard.settings,
                                   calendar: Std.calendar)
        _ = engine.handle(.launched(now: Std.t(6, 25)))
        let effects = engine.handle(.systemTable(table(Std.morning() + [stale]), now: Std.t(6, 25)))
        #expect(!engine.state.target.contains(stale))
        #expect(cancelled(effects) == [stale.id])
    }

    @Test("Review 1 (C6, C8): a lower-level ring in target never lowers the bar past the Deadline")
    func lowerLevelRingNeverLowersTheBar() {
        var engine = MorningEngine(state: EngineState(target: Std.morning() + [stale]),
                                   settings: SimFixture.standard.settings, calendar: Std.calendar)
        _ = engine.handle(.launched(now: Std.t(7, 15, 30)))
        _ = engine.handle(.tapStartChallenge(stale.id, now: Std.t(7, 15, 30)))
        #expect(engine.state.challenge?.level == 3)
        _ = engine.handle(.solved(ringID: stale.id, now: Std.t(7, 15, 50)))
        #expect(engine.state.finished[Std.today] == nil)
        var snoozing = MorningEngine(state: EngineState(target: Std.morning() + [stale]),
                                     settings: SimFixture.standard.settings, calendar: Std.calendar)
        _ = snoozing.handle(.launched(now: Std.t(7, 15, 30)))
        _ = snoozing.handle(.tapSnooze(stale.id, now: Std.t(7, 15, 30)))
        #expect(snoozing.screen != .none)
        #expect(snoozing.state.acknowledged.isEmpty)
    }

    @Test("Review 2 (A7, D2): a morning trimmed as the third armed one gets all 60 guards back once it is under way")
    func trimmedMorningToppedUpWhenUnderWay() {
        let settings = Self.threeHours.settings
        var evening = MorningEngine(state: EngineState(), settings: settings, calendar: Std.calendar)
        _ = evening.handle(.launched(now: Std.t(21, 0, day: 15)))
        #expect(guards(evening, day: 18) == 49)
        var later = MorningEngine(state: evening.state, settings: settings, calendar: Std.calendar)
        let firstGuard = Ring(date: Std.t(8, 1, day: 18), kind: .guardRing, level: 3, morning: Std.t(5, 0, day: 18),
                              challenge: .math)
        _ = later.handle(.alertAction(ringID: firstGuard.id, .openToChallenge, now: Std.t(8, 1, 5, day: 18)))
        _ = later.handle(.launched(now: Std.t(8, 1, 6, day: 18)))
        #expect(later.state.finished[Std.t(5, 0, day: 16)] == .missed)
        #expect(guards(later, day: 18) == 60)
        _ = later.handle(.tick(now: Std.t(9, 0, day: 18)))
        #expect(later.state.finished[Std.t(5, 0, day: 18)] == nil)
        #expect(later.underWay(at: Std.t(9, 0, day: 18))?.endsBy == Std.t(9, 10, day: 18))
    }

    @Test("Review 3/7 (R4): a schedule that keeps failing is retried while foreground, and the app sounds the ring")
    func failedScheduleRetriedAndSounded() {
        var engine = MorningEngine(state: EngineState(), settings: SimFixture.standard.settings, calendar: Std.calendar)
        let main = Std.main()
        _ = engine.handle(.launched(now: Std.t(21, 0, day: 15)))
        _ = engine.handle(.systemTable([], now: Std.t(21, 0, day: 15)))
        _ = engine.handle(.scheduled(main.id, ok: false, now: Std.t(21, 0, 1, day: 15)))
        var reads = 0
        var time = Std.t(21, 0, 5, day: 15)
        while time < Std.t(6, 40, day: 16) {
            if engine.handle(.tick(now: time)).contains(.readSystemTable) {
                reads += 1
                let held = engine.state.target.filter { $0.id != main.id && $0.date > time }
                let pass = engine.handle(.systemTable(table(held), now: time))
                #expect(scheduled(pass).map(\.id) == [main.id])
                _ = engine.handle(.scheduled(main.id, ok: false, now: time))
            }
            time = time.addingTimeInterval(5)
        }
        #expect(reads > 0)
        #expect(reads <= 600, "backoff: at most one read a minute")
        let effects = engine.handle(.tick(now: Std.t(6, 40, 5)))
        #expect(engine.screen == .ringing(main, sounding: true, snoozedUntil: nil))
        #expect(effects.contains(.sound(.play(nudge: false))))
        _ = engine.handle(.tick(now: Std.t(6, 41, 30)))
        #expect(engine.screen == .ringing(main, sounding: true, snoozedUntil: nil), "keeps sounding until tapped")
    }

    @Test("Review 4 (K2): switching to the Hebrew calendar does not give a third skip in one Gregorian month")
    func calendarSwitchKeepsSkipCount() {
        var ledger = SkipLedger()
        _ = ledger.use(at: Std.t(7, 0, day: 2), calendar: Std.calendar)
        _ = ledger.use(at: Std.t(7, 0, day: 5), calendar: Std.calendar)
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = Std.calendar.timeZone
        #expect(ledger.remaining(at: Std.t(6, 45), calendar: hebrew) == 0)
        var engine = MorningEngine(state: EngineState(target: Std.morning(), skips: ledger),
                                   settings: SimFixture.standard.settings, calendar: hebrew)
        _ = engine.handle(.skip(ringID: Std.main().id, now: Std.t(6, 45)))
        #expect(engine.state.finished[Std.today] == nil)
        #expect(ledger.remaining(at: Std.t(7, 0, day: 1, month: 12), calendar: hebrew) == 2)
    }

    @Test("Review 5 (A4): after a one-off finishes, a stale settings copy saying enabled does not re-arm it")
    func oneOffTurnOffSurvivesStaleSettings() {
        let oneOff = SimFixture.standard { $0.repeatDays = [] }.settings
        var engine = MorningEngine(state: EngineState(), settings: oneOff, calendar: Std.calendar)
        _ = engine.handle(.launched(now: Std.t(21, 0, day: 15)))
        _ = engine.handle(.tapStartChallenge(Std.main().id, now: Std.t(6, 40, 5)))
        let solve = engine.handle(.solved(ringID: Std.main().id, now: Std.t(6, 41)))
        #expect(Array(solve.prefix(2)) == [.persist, .disableAlarm], "disable straight after persist")
        let stale = engine.handle(.settingsChanged(oneOff, now: Std.t(6, 42)))
        #expect(stale.contains(.disableAlarm))
        #expect(engine.state.target.allSatisfy { $0.kind == .awakeCheck })
        // A kill before the app ran `.disableAlarm`: the next process still has enabled = true.
        var relaunched = MorningEngine(state: engine.state, settings: oneOff, calendar: Std.calendar)
        let launch = relaunched.handle(.launched(now: Std.t(6, 43)))
        #expect(launch.contains(.disableAlarm))
        #expect(relaunched.state.target.allSatisfy { $0.kind == .awakeCheck })
        #expect(relaunched.nextMorning(at: Std.t(6, 43)) == nil)
        // The app saved enabled = false; turning it on again arms tomorrow.
        var off = oneOff
        off.enabled = false
        _ = relaunched.handle(.settingsChanged(off, now: Std.t(12, 0)))
        _ = relaunched.handle(.settingsChanged(oneOff, now: Std.t(12, 1)))
        #expect(relaunched.nextMorning(at: Std.t(12, 1)) == Std.ideal(day: 17))
    }

    @Test("Review 6 (R2): with the persisted target lost mid-morning, today's rings in AlarmKit are adopted")
    func lostTargetAdoptsTheMorningUnderWay() {
        var engine = MorningEngine(state: EngineState(), settings: SimFixture.standard.settings, calendar: Std.calendar)
        let now = Std.t(6, 45)
        let held = Std.morning().filter { $0.date > now }
        _ = engine.handle(.launched(now: now))
        let effects = engine.handle(.systemTable(table(held), now: now))
        #expect(cancelled(effects).isEmpty)
        #expect(engine.activeMorning(at: now) == Std.today)
        #expect(ids(held).isSubset(of: ids(engine.state.target)))
        var finished = EngineState()
        finished.finished[Std.today] = .solved
        var done = MorningEngine(state: finished, settings: SimFixture.standard.settings, calendar: Std.calendar)
        _ = done.handle(.launched(now: now))
        let pass = done.handle(.systemTable(table(held), now: now))
        #expect(cancelled(pass) == ids(held), "a finished morning is never revived")
    }

    @Test("Review 8 (R2, D2): moving Ideal with three 3-hour mornings armed never holds more than 250 alarms")
    func passCancelsBeforeSchedulingFarMornings() {
        var sim = MorningSim(fixture: Self.threeHours, start: Std.t(21, 0, day: 15))
        sim.launch()
        let mark = sim.steps.count
        var count = sim.system.ids.count
        sim.changeSettings {
            $0.times = WakeTimes(ideal: ClockTime(hour: 5, minute: 5), deadline: ClockTime(hour: 8, minute: 5))
        }
        var peak = count
        for record in sim.steps[mark...] {
            for effect in record.effects {
                if case .schedule = effect { count += 1 }
                if case .cancel = effect { count -= 1 }
                peak = max(peak, count)
            }
        }
        #expect(peak <= ScheduleBudget.limit)
        #expect(sim.system.ids.count <= ScheduleBudget.limit)
        expectClean(sim)
    }

    @Test("Review 9 (I3): changing the deadline challenge reaches AlarmKit's metadata for armed mornings")
    func kindChangeReachesMetadata() {
        var sim = MorningSim.armed()
        sim.open()
        sim.changeSettings { $0.deadlineChallenge = .phrase }
        sim.settle()
        #expect(sim.liveSystem(kind: .deadline).map(\.challenge) == [.phrase, .phrase, .phrase])
        #expect(sim.liveSystem(kind: .guardRing).allSatisfy { $0.challenge == .phrase })
        expectClean(sim)
    }

    @Test("Review 10 (A3, D2): opening the app mid-morning does not trim a later morning the idle target held whole")
    func activeMorningCountsTowardArmedMornings() {
        var sim = MorningSim.armed(Self.threeHours)
        sim.advanceStoppingSnoozes(to: Std.t(6, 5))
        sim.open()
        sim.settle()
        let guardsBy = { (day: Int) in sim.liveSystem(kind: .guardRing, morning: Std.t(5, 0, day: day)).count }
        #expect(guardsBy(16) == 60)
        #expect(guardsBy(17) == 60)
        #expect(guardsBy(18) == 60)
        #expect(sim.system.ids.count <= ScheduleBudget.limit)
        expectClean(sim)
    }
}
