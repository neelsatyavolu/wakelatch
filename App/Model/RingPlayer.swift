import AVFoundation

/// The in-app sound that is playing, if any.
enum PlayingSound: String, Codable, Sendable {
    case chime
    case nudge
}

/// Plays the alarm sound in-app when Wakelatch takes over the ringing screen. AppModel drives it from the
/// engine's `.sound` effect only.
///
/// `playing` is what is really playing. A call, Siri or another app's audio can stop the player at any
/// time; the player restarts itself when that interruption ends, and AppModel asks again after every event
/// while the engine still wants the sound, so a takeover never leaves the morning silent.
@MainActor
final class RingPlayer: SoundPlaying {
    /// Under UI tests and unit tests: never touch the audio session or start a player, only keep `playing`
    /// up to date so tests can still check what would sound.
    private let silent: Bool
    private var player: AVAudioPlayer?
    /// The sound the engine asked for, whether or not it is playing right now.
    private var wanted: PlayingSound?
    private var observers: [any NSObjectProtocol] = []

    init(silent: Bool) {
        self.silent = silent
        guard !silent else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [AVAudioSession.interruptionNotification,
                                          AVAudioSession.mediaServicesWereResetNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notice in
                let began = Self.interruptionBegan(notice)
                MainActor.assumeIsolated { self?.audioSessionChanged(began: began) }
            }
        }
    }

    /// What is sounding now: nil when nothing was asked for, or when the player was stopped by an
    /// interruption or failed to start. Silent mode reports what would play.
    var playing: PlayingSound? {
        guard let wanted else { return nil }
        return silent || player?.isPlaying == true ? wanted : nil
    }

    /// Starts the chime (or the softer nudge sound). Switching from one to the other restarts it. Asking
    /// again for the sound that should be playing restarts a player that was stopped.
    func play(nudge: Bool) {
        let sound: PlayingSound = nudge ? .nudge : .chime
        if wanted == sound, playing != nil { return }
        player?.stop()
        player = nil
        wanted = sound
        guard !silent else { return }
        player = Self.startPlayer(for: sound)
    }

    func stop() {
        guard wanted != nil || player != nil else { return }
        wanted = nil
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The media volume is high enough to wake someone, so the system alarm can be silenced on takeover.
    static var volumeIsAudible: Bool {
        AVAudioSession.sharedInstance().outputVolume >= minimumVolume
    }

    private static let minimumVolume: Float = 0.5

    /// An interruption ended or the media services restarted: start the wanted sound again.
    private func audioSessionChanged(began: Bool) {
        guard !began, let wanted, playing == nil else { return }
        player = nil
        play(nudge: wanted == .nudge)
    }

    private nonisolated static func interruptionBegan(_ notice: Notification) -> Bool {
        guard notice.name == AVAudioSession.interruptionNotification,
              let raw = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return false }
        return AVAudioSession.InterruptionType(rawValue: raw) == .began
    }

    /// A looping player on an active playback session, or nil when the file or the session is unavailable.
    private static func startPlayer(for sound: PlayingSound) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else { return nil }
        do {
            // Playback category rings through the silent switch.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1
            return player.play() ? player : nil
        } catch {
            modelLog.error("In-app sound did not start: \(error.localizedDescription)")
            return nil
        }
    }
}
