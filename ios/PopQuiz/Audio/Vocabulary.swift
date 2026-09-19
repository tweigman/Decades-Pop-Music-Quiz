import Foundation
import PopQuizCore
import Speech

/// Builds a custom speech language model from every song title and artist,
/// plus the game's commands, numbers and categories, so the recognizer
/// expects "Blue Öyster Cult" rather than "blue oyster colt".
///
/// Training happens on the device and takes a little while the first time;
/// the result is cached and reused until the song list changes.
enum Vocabulary {
    static let clientID = "com.tweigman.popquiz"

    static func prepare(_ library: Library) async throws -> SFSpeechLanguageModel.Configuration {
        let phrases = phraseCounts(library)
        let version = String(stableHash(phrases.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")), radix: 36)
        let dir = URL.applicationSupportDirectory.appending(path: "Vocabulary")
        let asset = dir.appending(path: "popquiz-\(version).bin")
        let config = SFSpeechLanguageModel.Configuration(
            languageModel: dir.appending(path: "lm-\(version)"),
            vocabulary: dir.appending(path: "vocab-\(version)"))

        if !FileManager.default.fileExists(atPath: asset.path) {
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = SFCustomLanguageModelData(locale: Locale(identifier: "en_US"), identifier: clientID, version: version)
            for (phrase, count) in phrases {
                data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count))
            }
            try await data.export(to: asset)
        }
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: clientID, configuration: config)
        return config
    }

    /// Short phrases worth favouring without a custom model: commands and categories.
    static func contextualStrings(_ library: Library) -> [String] {
        Grading.commandPhrases + library.order.flatMap { categoryNames($0) }
    }

    private static func categoryNames(_ category: String) -> [String] {
        [category.replacingOccurrences(of: "_", with: " ")] + Settings.aliases(for: category)
    }

    private static func phraseCounts(_ library: Library) -> [(String, Int)] {
        var counts = [String: Int]()
        func add(_ phrase: String, _ count: Int) {
            let phrase = phrase.trimmingCharacters(in: .whitespaces)
            if !phrase.isEmpty { counts[phrase, default: 0] += count }
        }
        for song in library.allSongs {
            let bare = song.title.replacingOccurrences(of: #"\s*\([^)]*\)\s*"#, with: " ", options: .regularExpression)
            add(song.title, 10)
            if bare != song.title { add(bare, 10) }
            for artist in song.artists {
                add(artist, 10)
                add("\(bare) by \(artist)", 5)
                add("\(artist) \(bare)", 2)
            }
        }
        for phrase in Grading.commandPhrases { add(phrase, 50) }
        let numbers = ["one", "two", "three", "four", "five", "six"]
        for (i, n) in numbers.enumerated() {
            add(n, 30)
            add(i == 0 ? "one player" : "\(n) players", 30)
        }
        for category in library.order {
            for name in categoryNames(category) { add(name, 30) }
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// FNV-1a, so the cache key is the same on every launch (unlike hashValue).
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}
