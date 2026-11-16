import Foundation

/// Mornings starting, ending and being armed (rules A, L, G and W4).
extension MorningEngine {
    /// Ends mornings past their grace as missed (L3), drops expired awake checks (W4), and re-arms
    /// future mornings when a morning finished.
    mutating func housekeep(now: Date, out: inout EffectBuffer) {
        let spans = morningSpans()
        for morning in spans.keys.sorted() where state.finished[morning] == nil {
            if let span = spans[morning], now > span.endsBy(grace: settings.timing.grace) {
                finish(morning, .missed, upAt: nil, now: now, out: &out)
            }
        }
        let expiry = settings.timing.awakeCheckExpiry
        state.target.removeAll { $0.kind == .awakeCheck && now.timeIntervalSince($0.date) > expiry }
        if out.needsRefresh || activeNeedsGuards(now: now) {
            out.needsRefresh = false
            refreshTarget(now: now)
        }
    }

    /// Records the outcome once (L2, L4), removes the morning's rings from target and cancels the future ones.
    /// Finishing the one-off morning turns the alarm off (A4).
    mutating func finish(_ morning: Date, _ outcome: Outcome, upAt: Date?, now: Date, out: inout EffectBuffer) {
        guard state.finished[morning] == nil else { return }
        state.finished[morning] = outcome
        let record = MorningRecord(morning: morning, deadline: deadline(of: morning), outcome: outcome, upAt: upAt)
        state.records = Array((state.records + [record]).suffix(EngineState.recordLimit))
        let own = state.target.filter { $0.morning == morning && $0.kind != .awakeCheck }
        own.filter { $0.date > now }.forEach { out.cancel($0.id) }
        state.target.removeAll { $0.morning == morning && $0.kind != .awakeCheck }
        state.acknowledged.formIntersection(Set(state.target.map(\.id)))
        if state.challenge?.morning == morning { state.challenge = nil }
        if session.dismissedThisVisit.map({ id in own.contains { $0.id == id } }) == true {
            session.dismissedThisVisit = nil
        }
        if state.oneOffMorning == morning {
            state.oneOffMorning = nil
            state.turnedOff = now
            settings.enabled = false
            out.disableAlarm = true
        }
        out.needsRefresh = true
    }

    /// Rebuilds every morning except the ones under way (G1). Their rings, and awake checks, stay as they are,
    /// except that guards a budget trim left out come back (A7).
    mutating func refreshTarget(now: Date) {
        let spans = morningSpans()
        let active = activeMorning(at: now)
        let started = Set(spans.filter { state.finished[$0.key] == nil && $0.value.first <= now }.keys)
        let kept = toppedUp(state.target.filter { $0.kind == .awakeCheck || started.contains($0.morning) },
                            started: started)
        let endsBy = active.flatMap { spans[$0]?.endsBy(grace: settings.timing.grace) }
        let built = futureMornings(now: now, active: active, started: started)
            .map { buildRings(for: $0) }
            .filter { rings in endsBy.map { end in (rings.first?.date ?? .distantPast) > end } ?? true }
            .map { $0.filter { $0.date > now } }
            .filter { !$0.isEmpty }
        let reserved = kept.filter { $0.date > now }.count
        let trimmed = ScheduleBudget.trim(built, reserved: reserved)
        state.target = Self.sorted(kept + trimmed.flatMap { $0 })
    }

    /// The Ideals to arm after `now`, without the started and finished ones (A1-A6).
    private mutating func futureMornings(now: Date, active: Date?, started: Set<Date>) -> [Date] {
        let candidates = candidateMornings(now: now, active: active, started: started)
        return candidates.filter { state.finished[$0] == nil && !started.contains($0) }
    }

    /// A day whose morning already finished never yields a second morning, like the active day (A2).
    private func dayFinished(_ morning: Date, now: Date) -> Bool {
        let recent = now.addingTimeInterval(-2 * 86_400)
        return state.finished.keys.contains { $0 >= recent && calendar.isDate($0, inSameDayAs: morning) }
    }

    private mutating func candidateMornings(now: Date, active: Date?, started: Set<Date>) -> [Date] {
        guard settings.enabled else {
            if let oneOff = state.oneOffMorning, !started.contains(oneOff) { state.oneOffMorning = nil }
            return []
        }
        if let pinned = settings.pinnedMorning {
            return pinned > now ? [pinned] : []
        }
        guard settings.repeatDays.isEmpty else {
            state.oneOffMorning = nil
            // A morning under way counts toward `armedMornings`, so it never pushes a trim into later ones (A3).
            let count = max(0, settings.armedMornings - (active == nil ? 0 : 1))
            return Array(upcoming(now: now, active: active, count: count + 1)
                .filter { !dayFinished($0, now: now) && !started.contains($0) }
                .prefix(count))
        }
        return oneOffMornings(now: now, active: active, started: started)
    }

    /// One-off (A4): keep the stored morning while it is valid; otherwise pick and store the next one.
    private mutating func oneOffMornings(now: Date, active: Date?, started: Set<Date>) -> [Date] {
        if let oneOff = state.oneOffMorning {
            if started.contains(oneOff) { return [] }
            let unchanged = MorningPlan.idealDate(on: oneOff, times: settings.times, calendar: calendar) == oneOff
            if oneOff > now, unchanged, state.finished[oneOff] == nil { return [oneOff] }
            state.oneOffMorning = nil
        }
        let next = upcoming(now: now, active: active, count: 2)
            .first { !dayFinished($0, now: now) && !started.contains($0) }
        state.oneOffMorning = next
        return next.map { [$0] } ?? []
    }

    private func upcoming(now: Date, active: Date?, count: Int) -> [Date] {
        // A one-off searches every day, so a finished day can be passed over for the next one.
        MorningPlan.upcomingMornings(after: now, times: settings.times,
                                     repeatDays: settings.repeatDays.isEmpty ? Set(1...7) : settings.repeatDays,
                                     count: count, excluding: active, oneOff: nil, calendar: calendar)
    }

    /// Every ring of a morning from the current settings, or none when the window is too long (T6).
    func buildRings(for morning: Date) -> [Ring] {
        let window = MorningPlan.window(times: settings.times, timing: settings.timing)
        guard window <= TimeInterval(MorningPlan.maxWindowMinutes * 60) else { return [] }
        return MorningPlan.build(morning: morning, window: window, timing: settings.timing,
                                 challenges: settings.challenges)
    }

    static func sorted(_ rings: [Ring]) -> [Ring] {
        rings.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
}
