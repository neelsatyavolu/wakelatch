import Foundation
import WakelatchCore

/// A whole morning in memory: fake clock, fake AlarmKit, fake app process, and the real engine.
/// Every event runs the engine's effects against the fake AlarmKit (persisting first, honouring faults),
/// and every step is checked against INV1-INV10; violations collect in `violations`.
///
/// How the fake app behaves:
/// - `.schedule` lands at once and queues `.scheduled`, unless `faults.scheduleLatency` holds it in flight for
///   that many steps. The driver is serial: a `.cancel` or `.readSystemTable` issued while calls are in flight
///   waits behind them; otherwise it runs at once. A read queues `.systemTable` with the table as it is then.
/// - While foreground, every change to the alerting set is sent as `.alerting`, and a `.tick` arrives every
///   `tickInterval`. While suspended, killed or locked nothing is sent; alarms still fire in the fake.
/// - When the screen leaves `.none` in the foreground and no sheet is open, the cover presents and
///   `.coverShown` is sent. A sheet blocks the cover until `.dismissHomeSheets` closes it.
/// - A kill drops the engine, the event queue and every queued AlarmKit call; only `disk` survives. With
///   `faults.inFlightSurvivesKill`, the call at the head of the driver (already sent) lands after the next
///   process's first table read, and that read is then not fresh.
/// - Scheduling an id AlarmKit already holds replaces the alarm (assumed; not verified on device).
public struct MorningSim: Sendable {
    public let fixture: SimFixture
    /// The user's settings as the app would pass them to a new engine.
    public internal(set) var settings: EngineSettings
    public internal(set) var calendar: Calendar
    public internal(set) var now: Date
    public internal(set) var process: ProcessState
    /// What survives a kill: the last state saved by a `.persist` effect.
    public internal(set) var disk: EngineState
    /// Nil while killed.
    public internal(set) var engine: MorningEngine?
    public internal(set) var system: FakeAlarmKit
    public internal(set) var sound: SimSound
    public internal(set) var idleTimerDisabled: Bool
    public internal(set) var coverVisible: Bool
    public internal(set) var charging: Bool
    /// Every effect run, in order.
    public internal(set) var effectLog: [Effect]
    /// Every event the engine received, in order.
    public internal(set) var eventLog: [Event]
    /// Every event step with its effects and resulting screen.
    public internal(set) var steps: [SimRecord]
    public internal(set) var checker: InvariantChecker
    public var faults: SimFaults
    public var intentOrder: IntentOrder
    /// Whether the in-app chime is loud enough to silence the system alarm on takeover.
    public var audible: Bool
    /// Seconds between foreground ticks.
    public var tickInterval: TimeInterval

    var suspendedSurface: ForegroundSurface = .home
    var lockedFrom: ProcessState = .suspended
    var driver: [DriverOp] = []
    /// The call a killed process had already sent, waiting to land after the next table read.
    var orphaned: DriverOp.Kind?
    var queue: [QueueItem] = []
    var lastReportedAlerting: Set<UUID> = []
    var nextTick: Date?
    var faultCounter = 0
    var drain = DrainState()

    /// Starts killed at `start` with `disk` (empty by default). Call `launch()` to arm the alarms.
    public init(fixture: SimFixture = .standard, start: Date, faults: SimFaults = SimFaults(),
                intentOrder: IntentOrder = .afterActive, audible: Bool = true, disk: EngineState = EngineState()) {
        self.fixture = fixture
        self.settings = fixture.settings
        self.calendar = fixture.calendar
        self.now = start
        self.process = .killed
        self.disk = disk
        self.engine = nil
        self.system = FakeAlarmKit()
        self.sound = .silent
        self.idleTimerDisabled = false
        self.coverVisible = false
        self.charging = false
        self.effectLog = []
        self.eventLog = []
        self.steps = []
        self.checker = InvariantChecker()
        self.faults = faults
        self.intentOrder = intentOrder
        self.audible = audible
        self.tickInterval = 5
    }

    // MARK: observation

    /// The engine's screen; `.none` while killed.
    public var screen: Screen { engine?.screen ?? .none }
    /// The engine's state, or the disk while killed.
    public var state: EngineState { engine?.state ?? disk }
    public var alerting: Set<UUID> { system.alerting }
    public var records: [MorningRecord] { state.records }
    public var violations: [InvariantViolation] { checker.violations }
    public var isForeground: Bool {
        if case .foreground = process { return true }
        return false
    }

    /// Ring ids whose schedule is in flight.
    public var inFlight: Set<UUID> {
        Set(driver.compactMap { op -> UUID? in
            if case .schedule(let ring) = op.kind { return ring.id }
            return nil
        })
    }

    /// The open challenge, if the screen shows one.
    public var openChallenge: ActiveChallenge? {
        if case .challenge(let open) = screen { return open }
        return nil
    }

    /// Rings in the fake AlarmKit table, filtered by kind and morning, oldest first.
    public func liveSystem(kind: RingKind? = nil, morning: Date? = nil) -> [Ring] {
        system.live(kind: kind, morning: morning)
    }

    /// The morning (Ideal) on this calendar date, from the fixture's times.
    public func morning(_ year: Int, _ month: Int, _ day: Int) -> Date {
        SimCalendar.date(year, month, day, settings.times.ideal.hour, settings.times.ideal.minute, in: calendar)
    }

    /// The `index`th ring (0-based) of `kind` for `morning` in the engine's target (or the disk's), oldest first.
    public func ring(_ kind: RingKind, of morning: Date, index: Int = 0) -> Ring? {
        let rings = state.target.filter { $0.kind == kind && $0.morning == morning }.sorted { $0.date < $1.date }
        return rings.indices.contains(index) ? rings[index] : nil
    }

    // MARK: clock

    /// Moves the clock, firing alarms as their dates pass and sending a tick every `tickInterval` while
    /// foreground. Moving backwards does nothing.
    public mutating func advance(to date: Date) {
        guard date > now else { return }
        while true {
            var next = date
            if engine != nil, isForeground, let tick = nextTick, tick < next { next = tick }
            if let fire = system.nextFireDate(after: now), fire < next { next = fire }
            now = next
            let fired = system.advance(to: now)
            if engine != nil, isForeground {
                if !fired.isEmpty { queue.append(.alertingUpdate) }
                if let tick = nextTick, tick <= now {
                    nextTick = now.addingTimeInterval(max(tickInterval, 1))
                    queue.append(.event(.tick(now: now), fresh: false))
                }
                drainQueue()
            }
            if now >= date { break }
        }
    }

    public mutating func advance(by seconds: TimeInterval) {
        advance(to: now.addingTimeInterval(seconds))
    }
}

/// One AlarmKit call held by the serial driver.
struct DriverOp: Sendable {
    enum Kind: Sendable {
        case schedule(Ring)
        case cancel(UUID)
        case read
    }

    let kind: Kind
    var remaining: Int
}

/// Work waiting for the engine. `alertingUpdate` is resolved when it is delivered, so it carries the
/// alerting set and cover state of that moment.
enum QueueItem: Sendable {
    case event(Event, fresh: Bool)
    case alertingUpdate
}

/// What one drain of the queue saw, for the quiescent check.
struct DrainState: Sendable {
    var freshRead = false
    var targetChangedSinceRead = false
    var killed = false
    /// The engine handled at least one event at the drain's time, so its outputs are current (INV13).
    var delivered = false
}
