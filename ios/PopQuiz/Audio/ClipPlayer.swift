import AVFoundation
import PopQuizCore

enum ClipSource: String, CaseIterable, Identifiable {
    case bundled, stream
    var id: Self { self }
    var label: String { self == .bundled ? "On this iPhone" : "Stream from preview URL" }
}

enum ClipError: LocalizedError {
    case noURL, http(Int)
    var errorDescription: String? {
        switch self {
        case .noURL: "This song has no preview URL."
        case .http(let code): "The preview server answered \(code)."
        }
    }
}

/// Finds a song's audio (bundled or downloaded) and plays a window of it.
final class ClipPlayer {
    private var player: AVAudioPlayer?
    private let cacheDir = URL.cachesDirectory.appending(path: "clips")

    /// A local file for the song: the bundled clip when using bundled audio and
    /// it's present, otherwise a cached download of its preview URL.
    func file(for song: Song, source: ClipSource) async throws -> URL {
        if source == .bundled {
            let bundled = GameData.previewsDir.appending(path: song.file)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        let cached = cacheDir.appending(path: song.file)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard let remote = song.previewURL else { throw ClipError.noURL }
        let (download, response) = try await URLSession.shared.download(from: remote)
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { throw ClipError.http(code) }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: cached)
        try FileManager.default.moveItem(at: download, to: cached)
        return cached
    }

    /// Play `duration` seconds from `offset`, fading out at the end.
    /// Stops at once if the task is cancelled.
    func play(_ url: URL, from offset: Double, for duration: Double) async throws {
        let player = try AVAudioPlayer(contentsOf: url)
        self.player = player
        defer { player.stop() }
        player.currentTime = offset
        player.play()
        let fade = min(0.4, duration / 4)
        try await Task.sleep(for: .seconds(duration - fade))
        player.setVolume(0, fadeDuration: fade)
        try await Task.sleep(for: .seconds(fade))
    }

    /// Play a whole file, such as the bonus-round intro.
    func playAll(_ url: URL) async {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        defer { player.stop() }
        player.play()
        try? await Task.sleep(for: .seconds(player.duration))
    }

    func stop() { player?.stop() }
}
