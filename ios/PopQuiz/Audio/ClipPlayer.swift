import AVFoundation
import PopQuizCore

enum ClipError: LocalizedError {
    case noURL, http(Int)
    var errorDescription: String? {
        switch self {
        case .noURL: "This song has no preview URL."
        case .http(let code): "The preview server answered \(code)."
        }
    }
}

/// Streams a song's preview from Apple and plays a window of it. Nothing is
/// kept: previews sit in a temporary folder for the session, so a repeat
/// doesn't fetch twice, and the folder is emptied at every launch.
final class ClipPlayer {
    private var player: AVAudioPlayer?
    private let folder = FileManager.default.temporaryDirectory.appending(path: "previews")

    init() {
        try? FileManager.default.removeItem(at: folder)
        // Earlier versions cached clips here.
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "clips"))
    }

    /// The song's preview as a local file, fetched if it isn't here already.
    func file(for song: Song) async throws -> URL {
        guard let remote = song.previewURL else { throw ClipError.noURL }
        let type = remote.pathExtension.isEmpty ? "m4a" : remote.pathExtension
        let local = folder.appending(path: "\(song.id).\(type)")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        let (download, response) = try await URLSession.shared.download(from: remote)
        if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { throw ClipError.http(code) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: download, to: local)
        return local
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
