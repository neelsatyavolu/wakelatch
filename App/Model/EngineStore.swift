import Foundation
import WakelatchCore

/// Where `EngineState` is saved. AppModel saves before it runs any other effect of an event.
@MainActor
protocol EngineStoring: AnyObject {
    func load() -> EngineState?
    func save(_ state: EngineState) throws
}

/// `EngineState` as one JSON file. Each save writes a temporary file and renames it over the old one
/// (`Data.WritingOptions.atomic`), so a kill mid-write leaves the previous state, never half a file.
/// The file stays readable while the phone is locked after its first unlock, because alarm-button intents
/// can start the app on the lock screen.
@MainActor
final class EngineStore: EngineStoring {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Application Support/Wakelatch, created when missing.
    nonisolated static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appending(path: "Wakelatch", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// Nil when there is no file or it cannot be decoded.
    func load() -> EngineState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(EngineState.self, from: data)
        } catch {
            modelLog.error("Engine state unreadable, starting fresh: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ state: EngineState) throws {
        try FileStorage.write(state, to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Atomic JSON writes shared by the engine store and the alarm ledger.
enum FileStorage {
    static func write(_ value: some Encodable, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
