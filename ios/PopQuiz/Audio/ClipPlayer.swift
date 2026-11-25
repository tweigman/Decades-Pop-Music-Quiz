import AVFoundation
import PopQuizCore

enum ClipError: LocalizedError {
    case noURL, failed(Error?), timedOut
    var errorDescription: String? {
        switch self {
        case .noURL: "This song has no preview URL."
        case .failed(let error): error?.localizedDescription ?? "The preview couldn't be played."
        case .timedOut: "The preview took too long to load."
        }
    }
}

/// A preview that's buffered and waiting at the clip's start point.
final class PreparedClip: @unchecked Sendable {
    let player: AVPlayer
    init(_ player: AVPlayer) { self.player = player }
}

/// Streams a song's preview straight from Apple and plays a window of it.
/// Nothing is written to disk: Apple's terms for previews ask that they be
/// streamed, not downloaded.
final class ClipPlayer {
    private var current: AVPlayer?
    private var effect: AVAudioPlayer?

    init() {
        // Versions before 2.0.2 downloaded previews to these folders.
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "previews"))
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "clips"))
    }

    /// Open the stream, seek to the clip's start and buffer enough to begin
    /// at once. Done while the question is being read out.
    func prepare(_ clip: Clip) async throws -> PreparedClip {
        guard let url = clip.song.previewURL else { throw ClipError.noURL }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = clip.duration + 1
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(15)
        while item.status != .readyToPlay {
            if item.status == .failed { throw ClipError.failed(item.error) }
            if clock.now > deadline { throw ClipError.timedOut }
            try await Task.sleep(for: .milliseconds(50))
        }
        let start = CMTime(seconds: clip.offset, preferredTimescale: 600)
        _ = await player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await player.preroll(atRate: 1)
        try Task.checkCancellation()
        return PreparedClip(player)
    }

    /// Play `duration` seconds of a prepared clip, fading out at the end.
    /// Stops at once if the task is cancelled.
    func play(_ clip: PreparedClip, for duration: Double) async throws {
        let player = clip.player
        current = player
        defer { player.pause() }
        player.volume = 1
        player.play()
        let fade = min(0.4, duration / 4)
        try await Task.sleep(for: .seconds(duration - fade))
        let steps = 8
        for step in 1...steps {
            player.volume = Float(steps - step) / Float(steps)
            try await Task.sleep(for: .seconds(fade / Double(steps)))
        }
    }

    /// Play a short sound held in memory, such as the bonus-round intro.
    func playAll(_ data: Data) async {
        guard let player = try? AVAudioPlayer(data: data) else { return }
        effect = player
        defer { player.stop() }
        player.play()
        try? await Task.sleep(for: .seconds(player.duration))
    }

    func stop() {
        current?.pause()
        effect?.stop()
    }
}
