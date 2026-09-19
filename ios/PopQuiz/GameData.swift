import Foundation

/// The song data copied into the app by scripts/bundle_game_data.sh.
enum GameData {
    static let dir = Bundle.main.bundleURL.appending(path: "GameData")
    static let previewsDir = dir.appending(path: "previews")

    static var bonusIntro: URL? {
        let url = dir.appending(path: "sounds/bonus_intro.mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether this build carries the MP3 clips (BUNDLE_CLIPS = YES).
    static let hasBundledClips: Bool = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: previewsDir.path)) ?? []
        return files.contains { $0.hasSuffix(".mp3") }
    }()
}
