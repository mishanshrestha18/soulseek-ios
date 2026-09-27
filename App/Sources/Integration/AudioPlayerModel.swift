import AVFoundation
import Foundation
import Observation

/// Plays a completed download in place.
///
/// Uses a polling ticker rather than `addPeriodicTimeObserver`, whose callback
/// is a `@Sendable` closure delivered on an arbitrary queue — awkward to reconcile
/// with this being MainActor-isolated. A Task started here inherits MainActor,
/// so reading the player and publishing the time needs no hopping.
@MainActor
@Observable
final class AudioPlayerModel {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var ticker: Task<Void, Never>?

    /// Seconds a skip moves by, matching the podcast-app convention.
    static let skipInterval: Double = 10

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
    }

    func isCurrent(_ url: URL) -> Bool { currentURL == url }

    // MARK: - Playback

    func play(url: URL) async {
        if currentURL != url {
            await load(url)
        }
        activateSession()
        player?.play()
        isPlaying = true
        startTicking()
    }

    func toggle(url: URL) async {
        if currentURL == url, isPlaying {
            pause()
        } else {
            await play(url: url)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    func skip(by seconds: Double) {
        guard let player else { return }
        let target = max(0, min(duration, player.currentTime().seconds + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0, let player else { return }
        let target = max(0, min(duration, duration * fraction))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    func stop() {
        pause()
        player = nil
        currentURL = nil
        currentTime = 0
        duration = 0
    }

    // MARK: - Internals

    private func load(_ url: URL) async {
        pause()
        let asset = AVURLAsset(url: url)
        // A partially written or unsupported file yields no duration; treating
        // that as zero keeps the scrubber inert rather than wrong.
        duration = (try? await asset.load(.duration))?.seconds ?? 0
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        currentURL = url
        currentTime = 0
    }

    /// `.playback` so audio is audible with the ring/silent switch on mute and
    /// keeps going when the screen locks.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime().seconds

                // AVPlayer stays "playing" at the end of an item, so the button
                // would keep showing pause on a track that has finished.
                if self.duration > 0, self.currentTime >= self.duration - 0.25 {
                    self.pause()
                    return
                }
            }
        }
    }
}
