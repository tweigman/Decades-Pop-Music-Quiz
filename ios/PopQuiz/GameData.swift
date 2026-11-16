import Foundation

/// The song lists copied into the app by scripts/bundle_game_data.sh.
enum GameData {
    static let dir = Bundle.main.bundleURL.appending(path: "GameData")
    static let categoriesDir = dir.appending(path: "categories")

    static var bonusIntro: URL? {
        let url = dir.appending(path: "sounds/bonus_intro.mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
