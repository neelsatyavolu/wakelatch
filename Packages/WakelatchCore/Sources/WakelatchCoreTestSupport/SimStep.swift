import Foundation
import WakelatchCore

/// The global invariants from docs/morning-contract.md section 15.
public enum Invariant: String, Hashable, Sendable, CaseIterable {
    case inv1, inv2, inv3, inv4, inv5, inv6, inv7, inv8, inv9, inv10, inv11, inv12, inv13
}

public struct InvariantViolation: Hashable, Sendable, CustomStringConvertible {
    public let invariant: Invariant
    public let at: Date
    public let detail: String

    public init(invariant: Invariant, at: Date, detail: String) {
        self.invariant = invariant
        self.at = at
        self.detail = detail
    }

    public var description: String { "\(invariant.rawValue) at \(at): \(detail)" }
}

/// One simulated step, as the checker sees it. An event step has `event`; a quiescent check, taken once the
/// event queue has drained, has `event == nil`.
public struct SimStep: Sendable {
    public let now: Date
    public let event: Event?
    /// The effects of this event that ran (fewer than the engine returned when a fault killed the process).
    public let effects: [Effect]
    /// The process when the event was delivered, and after its effects ran.
    public let processBefore: ProcessState
    public let process: ProcessState
    public let before: EngineState
    public let after: EngineState
    public let screenBefore: Screen
    public let screen: Screen
    public let session: SessionState
    public let systemBefore: FakeAlarmKit
    public let system: FakeAlarmKit
    /// Whether the morning cover was visible when the event was delivered.
    public let coverVisible: Bool
    /// Ring ids handed to the fake AlarmKit whose schedule has not landed yet.
    public let inFlight: Set<UUID>
    /// The event queue has drained and the process is alive (INV2 is checked only then).
    public let quiescent: Bool
    /// A fresh reconcile pass landed in this drain with no target change after it (INV5, INV7, INV8).
    public let reconcileSettled: Bool
    /// The in-app chime and idle timer as the app last set them (INV13).
    public let sound: SimSound
    public let idleTimerDisabled: Bool
    /// The engine handled an event at `now` in this drain, so the sound and idle timer it last sent were
    /// computed at `now` (between events the idle timer is only re-evaluated on the next tick).
    public let outputsCurrent: Bool

    public init(now: Date, event: Event?, effects: [Effect], processBefore: ProcessState, process: ProcessState,
                before: EngineState, after: EngineState, screenBefore: Screen, screen: Screen,
                session: SessionState, systemBefore: FakeAlarmKit, system: FakeAlarmKit, coverVisible: Bool,
                inFlight: Set<UUID>, quiescent: Bool, reconcileSettled: Bool, sound: SimSound = .silent,
                idleTimerDisabled: Bool = false, outputsCurrent: Bool = true) {
        self.now = now
        self.sound = sound
        self.idleTimerDisabled = idleTimerDisabled
        self.outputsCurrent = outputsCurrent
        self.event = event
        self.effects = effects
        self.processBefore = processBefore
        self.process = process
        self.before = before
        self.after = after
        self.screenBefore = screenBefore
        self.screen = screen
        self.session = session
        self.systemBefore = systemBefore
        self.system = system
        self.coverVisible = coverVisible
        self.inFlight = inFlight
        self.quiescent = quiescent
        self.reconcileSettled = reconcileSettled
    }

    var isForeground: Bool {
        if case .foreground = process { return true }
        return false
    }
}

/// One line of the sim's step log.
public struct SimRecord: Sendable {
    public let now: Date
    public let event: Event
    public let effects: [Effect]
    public let screen: Screen
    public let stateChanged: Bool
    public let targetChanged: Bool
    /// A fault killed the process part-way through this event's effects, so `effects` is incomplete.
    public let truncated: Bool

    public init(now: Date, event: Event, effects: [Effect], screen: Screen, stateChanged: Bool, targetChanged: Bool,
                truncated: Bool = false) {
        self.now = now
        self.event = event
        self.effects = effects
        self.screen = screen
        self.stateChanged = stateChanged
        self.targetChanged = targetChanged
        self.truncated = truncated
    }
}

extension Effect {
    var silencedID: UUID? {
        if case .silence(let id) = self { return id }
        return nil
    }
}
