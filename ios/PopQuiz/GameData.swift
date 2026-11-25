import Foundation

/// The song lists copied into the app by scripts/bundle_game_data.sh.
enum GameData {
    static let dir = Bundle.main.bundleURL.appending(path: "GameData")
    static let categoriesDir = dir.appending(path: "categories")

    /// The bonus-round intro. It's a licensed sound, so it's stored scrambled
    /// (see scripts/bundle_game_data.sh) rather than as a playable file
    /// anyone could copy out of the app.
    static let bonusIntro: Data? = {
        guard let data = try? Data(contentsOf: dir.appending(path: "sounds/bonus.bin")) else { return nil }
        return Data(data.map { $0 ^ scrambleKey })
    }()

    static let scrambleKey: UInt8 = 0xA7
}
