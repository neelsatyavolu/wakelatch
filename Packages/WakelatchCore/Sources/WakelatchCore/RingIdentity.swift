import CryptoKit
import Foundation

/// Deterministic ring ids, so a reconcile pass that was interrupted can simply run again.
public enum RingIdentity {
    /// Bumped only if the hashed fields change; old ids then stop matching and are reconciled away.
    /// v2 added the level and the snapshotted challenge, so a ring whose metadata changes gets a new id.
    public static let version = "v2"

    /// Fixed namespace for Wakelatch ring ids (RFC 4122 name-based UUIDs need one).
    static let namespace = UUID(uuid: (0x6F, 0x3B, 0x2C, 0x1E, 0x9A, 0x4D, 0x4B, 0x8E,
                                       0xA1, 0xC7, 0x5D, 0x2E, 0x8F, 0x0B, 0x3A, 0x94))

    /// Name-based UUID (version 5, SHA-1) over "v2|<morning epoch seconds>|<kind raw value>|
    /// <date epoch seconds>|<group or ->|<level>|<challenge raw value or ->".
    /// Same inputs always give the same UUID; any differing input gives a different one. Every field that
    /// travels in AlarmKit's metadata is hashed, so an id in the table always carries current metadata (I3).
    public static func id(morning: Date, kind: RingKind, date: Date, group: Int?, level: Int,
                          challenge: ChallengeKind?) -> UUID {
        let name = [version, epoch(morning), kind.rawValue, epoch(date), group.map(String.init) ?? "-",
                    String(level), challenge?.rawValue ?? "-"]
            .joined(separator: "|")
        return uuidV5(name: name)
    }

    /// Whole seconds since 1970. Rings of one morning are always at least seconds apart.
    static func epoch(_ date: Date) -> String {
        String(Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    static func uuidV5(name: String) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var b = Array(Insecure.SHA1.hash(data: data).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
