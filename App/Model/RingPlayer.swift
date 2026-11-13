import AVFoundation

/// Plays the alarm sound in-app when Wakelatch takes over the ringing screen.
@MainActor
final class RingPlayer {
    static let shared = RingPlayer()
    private var player: AVAudioPlayer?

    func play(nudge: Bool) {
        guard player?.isPlaying != true,
              let url = Bundle.main.url(forResource: nudge ? "nudge" : "chime", withExtension: "caf") else { return }
        do {
            // Playback category rings through the silent switch.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    /// Quieter while the user works on the challenge.
    func duck(_ ducked: Bool) {
        player?.setVolume(ducked ? 0.25 : 1, fadeDuration: 0.4)
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
