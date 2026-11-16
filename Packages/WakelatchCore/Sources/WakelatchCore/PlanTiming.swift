import Foundation

/// Every spacing the engine uses, in seconds, so UI tests can compress a whole morning into minutes.
public struct PlanTiming: Codable, Hashable, Sendable {
    /// Nudges, as seconds before Ideal. Empty when nudges are off.
    public var nudgeOffsets: [TimeInterval]
    /// Gap between snooze rings. Long windows widen it so there are at most `maxSnoozes`.
    public var snoozeSpacing: TimeInterval
    public var maxSnoozes: Int
    /// A snooze closer than this to the Deadline is dropped.
    public var snoozeDeadlineGap: TimeInterval
    /// Gap between guard rings after the Deadline.
    public var guardSpacing: TimeInterval
    /// Guards ring until this long after the Deadline (D2).
    public var guardWindow: TimeInterval
    /// After the last guard, how long the morning stays open before it ends as missed.
    public var grace: TimeInterval
    /// Awake checks, as seconds after the solve.
    public var awakeOffsets: [TimeInterval]
    /// Guard rings after each awake check.
    public var awakeGuards: Int
    public var awakeGuardSpacing: TimeInterval
    /// An unanswered awake-check ring older than this is dropped.
    public var awakeCheckExpiry: TimeInterval
    /// Ideal-to-Deadline window to use instead of the one from WakeTimes (UI tests). Nil in production.
    public var windowOverride: TimeInterval?
    /// A route from an alert button older than this is ignored.
    public var routeMaxAge: TimeInterval
    /// The in-app nudge screen clears itself this long after it first showed.
    public var nudgeScreenCap: TimeInterval
    /// The Released screen keeps the display awake for this long after the solve.
    public var releasedKeepAwake: TimeInterval

    public init(nudgeOffsets: [TimeInterval], snoozeSpacing: TimeInterval, maxSnoozes: Int,
                snoozeDeadlineGap: TimeInterval, guardSpacing: TimeInterval, guardWindow: TimeInterval,
                grace: TimeInterval, awakeOffsets: [TimeInterval], awakeGuards: Int,
                awakeGuardSpacing: TimeInterval, awakeCheckExpiry: TimeInterval,
                windowOverride: TimeInterval?, routeMaxAge: TimeInterval,
                nudgeScreenCap: TimeInterval, releasedKeepAwake: TimeInterval) {
        self.nudgeOffsets = nudgeOffsets
        self.snoozeSpacing = snoozeSpacing
        self.maxSnoozes = maxSnoozes
        self.snoozeDeadlineGap = snoozeDeadlineGap
        self.guardSpacing = guardSpacing
        self.guardWindow = guardWindow
        self.grace = grace
        self.awakeOffsets = awakeOffsets
        self.awakeGuards = awakeGuards
        self.awakeGuardSpacing = awakeGuardSpacing
        self.awakeCheckExpiry = awakeCheckExpiry
        self.windowOverride = windowOverride
        self.routeMaxAge = routeMaxAge
        self.nudgeScreenCap = nudgeScreenCap
        self.releasedKeepAwake = releasedKeepAwake
    }

    /// Guard rings per morning: one every `guardSpacing` up to `guardWindow` after the Deadline.
    public var guardCount: Int {
        guardSpacing > 0 ? Int((guardWindow / guardSpacing).rounded(.down)) : 0
    }

    /// The shipping timing. `options.guardRings` is ignored: guards run for 60 minutes (D2).
    public static func production(_ options: PlanOptions) -> PlanTiming {
        PlanTiming(
            nudgeOffsets: options.nudges ? [20 * 60, 10 * 60] : [],
            snoozeSpacing: TimeInterval(options.snoozeMinutes * 60),
            maxSnoozes: PlanOptions.maxSnoozeRings,
            snoozeDeadlineGap: 60,
            guardSpacing: 60,
            guardWindow: 60 * 60,
            grace: 10 * 60,
            awakeOffsets: [5 * 60, 12 * 60],
            awakeGuards: 3,
            awakeGuardSpacing: 60,
            awakeCheckExpiry: 15 * 60,
            windowOverride: nil,
            routeMaxAge: 120,
            nudgeScreenCap: 5 * 60,
            releasedKeepAwake: 60)
    }

    /// UI-test morning of about four minutes. With launch time L and Ideal = L + 60 s:
    /// nudges at Ideal-40 and Ideal-20, snoozes at +40 (L1) and +80 (L2), Deadline at +120,
    /// guards at +145, +170, +195, grace 30 s, awake checks at solve+30 and solve+70 with 2 guards 20 s apart.
    /// Set `nudgeOffsets = []` for the no-nudge profile.
    public static let compressed = PlanTiming(
        nudgeOffsets: [40, 20],
        snoozeSpacing: 40,
        maxSnoozes: PlanOptions.maxSnoozeRings,
        snoozeDeadlineGap: 20,
        guardSpacing: 25,
        guardWindow: 75,
        grace: 30,
        awakeOffsets: [30, 70],
        awakeGuards: 2,
        awakeGuardSpacing: 20,
        awakeCheckExpiry: 120,
        windowOverride: 120,
        routeMaxAge: 120,
        nudgeScreenCap: 60,
        releasedKeepAwake: 30)
}
