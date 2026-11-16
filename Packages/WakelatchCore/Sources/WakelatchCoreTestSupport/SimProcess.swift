import Foundation
import WakelatchCore

/// Sheets that can sit over the home screen.
public enum HomeSheet: Hashable, Sendable, CaseIterable {
    case settings, time
}

/// What is on screen while the app is in the foreground.
public enum ForegroundSurface: Hashable, Sendable {
    case home
    case bedside
    case sheet(HomeSheet)
}

/// The simulated app process.
public enum ProcessState: Hashable, Sendable {
    /// Not running. Only the persisted `EngineState` survives.
    case killed
    /// In memory, not active. The engine keeps its state.
    case suspended
    case foreground(ForegroundSurface)
    /// Device locked. `cancelUnlock`: a foreground intent asks for Face ID and the user cancels it,
    /// so the app never comes forward and the intent does not run.
    case locked(cancelUnlock: Bool)
}

/// When an alert intent's `alertAction` reaches the engine relative to the app coming forward.
public enum IntentOrder: Hashable, Sendable, CaseIterable {
    case beforeActive
    case afterActive
    case afterFirstTick
}

/// Faults injected into the fake AlarmKit and process.
public struct SimFaults: Hashable, Sendable {
    /// Kill the process right after the nth effect (0-based count of effects run) of the next event.
    public var killAfterEffect: Int?
    /// Number of other simulated steps that run while each `.schedule` effect is in flight.
    public var scheduleLatency: Int
    /// Ring ids whose schedule fails.
    public var scheduleFails: Set<UUID>
    /// Number of other simulated steps that run while each `.cancel` effect is in flight.
    public var cancelLatency: Int
    /// A kill does not stop the AlarmKit call the driver was awaiting (it already reached the system): it
    /// lands right after the next process's first table read, so that read is stale. Its reply goes nowhere.
    public var inFlightSurvivesKill: Bool

    public init(killAfterEffect: Int? = nil, scheduleLatency: Int = 0, scheduleFails: Set<UUID> = [],
                cancelLatency: Int = 0, inFlightSurvivesKill: Bool = false) {
        self.killAfterEffect = killAfterEffect
        self.scheduleLatency = scheduleLatency
        self.scheduleFails = scheduleFails
        self.cancelLatency = cancelLatency
        self.inFlightSurvivesKill = inFlightSurvivesKill
    }
}

/// The in-app chime as the sim last heard it.
public enum SimSound: Hashable, Sendable {
    case silent
    case playing(nudge: Bool)
}
