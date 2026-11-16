import Foundation

/// The engine's planning functions. The older `build(on:times:options:calendar:)` and `upcomingDays`
/// stay for the app until it moves to the engine.
extension MorningPlan {
    /// Every ring of one morning, oldest first, with deterministic ids and snapshotted challenge kinds.
    /// - nudges at Ideal minus each `timing.nudgeOffsets` (level 0);
    /// - main at Ideal (level 1) when `window > 0`;
    /// - snoozes every `snoozeSpacing` (widened to `ceil(window / maxSnoozes)`), level 1 while the offset is
    ///   at most half the window and 2 after, dropped when closer than `snoozeDeadlineGap` to the Deadline;
    /// - the deadline at Ideal + window (level 3);
    /// - `timing.guardCount` guards every `guardSpacing` after the Deadline (level 3).
    public static func build(morning ideal: Date, window: TimeInterval, timing: PlanTiming,
                             challenges: ChallengeSnapshot) -> [Ring] {
        let deadline = ideal.addingTimeInterval(window)
        var rings = timing.nudgeOffsets.sorted(by: >).map {
            Ring(date: ideal.addingTimeInterval(-$0), kind: .nudge, level: 0, morning: ideal)
        }
        if window > 0 {
            rings.append(Ring(date: ideal, kind: .main, level: 1, morning: ideal, challenge: challenges.snooze))
            rings += snoozes(ideal: ideal, window: window, timing: timing, kind: challenges.snooze)
        }
        rings.append(Ring(date: deadline, kind: .deadline, level: 3, morning: ideal, challenge: challenges.deadline))
        if timing.guardCount > 0 {
            rings += (1...timing.guardCount).map {
                Ring(date: deadline.addingTimeInterval(Double($0) * timing.guardSpacing), kind: .guardRing,
                     level: 3, morning: ideal, challenge: challenges.deadline)
            }
        }
        return rings
    }

    private static func snoozes(ideal: Date, window: TimeInterval, timing: PlanTiming,
                                kind: ChallengeKind) -> [Ring] {
        let widened = timing.maxSnoozes > 0 ? (window / Double(timing.maxSnoozes)).rounded(.up) : window
        let spacing = max(timing.snoozeSpacing, widened)
        guard spacing > 0 else { return [] }
        var rings: [Ring] = []
        var offset = spacing
        while offset < window, window - offset >= timing.snoozeDeadlineGap {
            rings.append(Ring(date: ideal.addingTimeInterval(offset), kind: .snooze,
                              level: 2 * offset <= window ? 1 : 2, morning: ideal, challenge: kind))
            offset += spacing
        }
        return rings
    }

    /// The morning whose Ideal falls on `day`'s calendar date. The window is `timing.windowOverride`
    /// when set, otherwise `times.windowMinutes`. Throws `PlanError.windowTooLong` past 3 hours.
    public static func build(on day: Date, times: WakeTimes, timing: PlanTiming,
                             challenges: ChallengeSnapshot, calendar: Calendar) throws -> [Ring] {
        let window = window(times: times, timing: timing)
        guard window <= TimeInterval(maxWindowMinutes * 60) else { throw PlanError.windowTooLong }
        let ideal = idealDate(on: day, times: times, calendar: calendar)
        return build(morning: ideal, window: window, timing: timing, challenges: challenges)
    }

    /// Ideal-to-Deadline window in seconds for these settings.
    public static func window(times: WakeTimes, timing: PlanTiming) -> TimeInterval {
        timing.windowOverride ?? TimeInterval(times.windowMinutes * 60)
    }

    /// The Ideal dates of the next mornings to arm, oldest first.
    /// - A day qualifies while its Ideal is still after `now` (the first nudge does not count).
    /// - The calendar day of `active` (a morning under way) never qualifies. Mornings that would start
    ///   before `active`'s last ring plus grace are filtered by the engine, which knows the timing.
    /// - `repeatDays` uses Calendar weekdays (1 = Sunday); empty means a one-off morning: the result is
    ///   `[oneOff]` when `oneOff` is set and still ahead, `[]` when it is set and passed, and otherwise
    ///   the single next qualifying morning.
    /// - At most `count` mornings, searched over the next 15 days.
    public static func upcomingMornings(after now: Date, times: WakeTimes, repeatDays: Set<Int>, count: Int,
                                        excluding active: Date?, oneOff: Date?, calendar: Calendar) -> [Date] {
        let sameDayAsActive = { (ideal: Date) in active.map { calendar.isDate(ideal, inSameDayAs: $0) } ?? false }
        if repeatDays.isEmpty, let oneOff {
            return oneOff > now && !sameDayAsActive(oneOff) ? [oneOff] : []
        }
        let limit = repeatDays.isEmpty ? 1 : count
        var mornings: [Date] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<15 where mornings.count < limit {
            let ideal = idealDate(on: day, times: times, calendar: calendar)
            let weekday = calendar.component(.weekday, from: day)
            if ideal > now, repeatDays.isEmpty || repeatDays.contains(weekday), !sameDayAsActive(ideal) {
                mornings.append(ideal)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return mornings
    }

    /// Awake-check rings for a morning solved at `solvedAt`: for each `timing.awakeOffsets[g]`, a check at
    /// solvedAt + offset and `awakeGuards` guards `awakeGuardSpacing` apart, all with `checkGroup = g`, level 0.
    public static func awakeChecks(morning: Date, solvedAt: Date, timing: PlanTiming) -> [Ring] {
        timing.awakeOffsets.enumerated().flatMap { group, offset in
            (0...max(0, timing.awakeGuards)).map { step in
                Ring(date: solvedAt.addingTimeInterval(offset + Double(step) * timing.awakeGuardSpacing),
                     kind: .awakeCheck, level: 0, morning: morning, checkGroup: group)
            }
        }
    }
}
