// Understanding what the player said: answers, commands, numbers, categories.
// A port of custom_components/popquiz/grading.py; the parity tests check it
// against the Python version's decisions.
//
// Everything works on text from speech-to-text, so matching is forgiving:
// case, punctuation, accents, digits-vs-words and small misspellings are
// ignored. Names are matched against word-aligned windows of the utterance, so
// "imagine by john lennon" matches both "Imagine" and "John Lennon", but
// "imagination" does not match "Imagine".

import Foundation

public enum Grading {
    private static let digitWords = (
        "zero one two three four five six seven eight nine ten eleven twelve "
        + "thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"
    ).split(separator: " ").map(String.init)

    private static let playerCountWords: [String: Int] = {
        var words = Dictionary(uniqueKeysWithValues: digitWords.enumerated().map { ($1, $0) })
        words.merge(["won": 1, "to": 2, "too": 2, "for": 4, "solo": 1, "me": 1]) { $1 }
        return words
    }()

    private static let exitPhrases = ["exit game now", "exit game", "exit the game", "quit game", "stop game"]
    private static let skipPhrases = ["skip", "skip it", "skip this one", "skip please", "pass", "i pass"]
    private static let repeatPhrases = [
        "repeat", "repeat it", "repeat that", "repeat please", "play it again", "say that again",
    ]

    /// Every word the game listens for outside of song names.
    public static var commandPhrases: [String] { exitPhrases + skipPhrases + repeatPhrases }

    private static let bangInWord = try! NSRegularExpression(pattern: #"(?<=\w)!(?=\w)"#)
    private static let dollarInWord = try! NSRegularExpression(pattern: #"(?<=\w)\$(?=\w)"#)
    private static let nonAlphanumeric = try! NSRegularExpression(pattern: "[^a-z0-9]+")
    private static let parenthesised = try! NSRegularExpression(pattern: #"\([^)]*\)"#)

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Lowercase, strip accents and punctuation, spell out small numbers.
    public static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars
        where scalar.properties.canonicalCombiningClass == .notReordered {
            scalars.append(scalar)
        }
        var text = String(scalars).lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "&", with: " and ")
        // P!nk -> pink, Ke$ha -> kesha
        text = replace(bangInWord, in: text, with: "i")
        text = replace(dollarInWord, in: text, with: "s")
        text = text.replacingOccurrences(of: "'", with: "")
        text = replace(nonAlphanumeric, in: text, with: " ")
        return text.split(separator: " ").map { word in
            if word.allSatisfy(\.isASCII), let n = Int(word), n < digitWords.count {
                return digitWords[n]
            }
            return String(word)
        }.joined(separator: " ")
    }

    static func ratio(_ a: String, _ b: String) -> Double {
        SequenceMatcher.ratio(Array(a.utf8), Array(b.utf8)) * 100
    }

    /// Acceptable ways to say a name: with/without (parentheses), leading "the".
    static func variants(_ name: String) -> Set<String> {
        var out: Set<String> = [normalize(name), normalize(replace(parenthesised, in: name, with: " "))]
        for v in out where v.hasPrefix("the ") && v.count > 4 {
            out.insert(String(v.dropFirst(4)))
        }
        return out.filter { !$0.isEmpty }
    }

    /// A bracketed part of a title that's only a label, not a way to name the
    /// song: "(Part 1)", "(From "Batman")", "(Remix)".
    private static let labelWords: Set<String> = [
        "from", "part", "feat", "featuring", "with", "remix", "mix", "version",
        "edit", "live", "remaster", "remastered", "mono", "stereo",
    ]
    private static let bracketed = try! NSRegularExpression(pattern: #"\(([^)]*)\)"#)

    /// As `variants`, and a bracketed part alone also names the song:
    /// "(Sweet Sweet Baby) Since You've Been Gone" is right as "Sweet Sweet
    /// Baby", "Since You've Been Gone", or both. Labels like "(Part 1)" don't
    /// count, nor single short words.
    static func titleVariants(_ title: String) -> Set<String> {
        var out = variants(title)
        let range = NSRange(title.startIndex..., in: title)
        for match in bracketed.matches(in: title, range: range) {
            guard let inner = Range(match.range(at: 1), in: title) else { continue }
            let words = normalize(String(title[inner])).split(separator: " ").map(String.init)
            guard let first = words.first, !labelWords.contains(first),
                labelWords.isDisjoint(with: words) else { continue }
            if words.count >= 2 || first.count >= 6 { out.insert(words.joined(separator: " ")) }
        }
        return out
    }

    /// Best match of target against any run of words in said.
    static func bestWindowScore(_ target: String, _ said: String) -> Double {
        let words = said.split(separator: " ")
        guard !words.isEmpty else { return 0 }
        if target.replacingOccurrences(of: " ", with: "").count <= Settings.shortNameLength {
            return " \(said) ".contains(" \(target) ") ? 100 : 0
        }
        let squashedTarget = target.replacingOccurrences(of: " ", with: "")
        let n = target.split(separator: " ").count
        var best = 0.0
        for size in max(1, n - 1)..<(n + 2) {
            for i in 0..<max(1, words.count - size + 1) {
                let window = words[i..<min(i + size, words.count)].joined(separator: " ")
                best = max(best, ratio(target, window))
                // Speech-to-text sometimes splits or joins words ("pop quiz"/"popquiz").
                best = max(best, ratio(squashedTarget, window.replacingOccurrences(of: " ", with: "")))
            }
        }
        return best
    }

    private static let genericSurnames: Set<String> = [
        "brothers", "sisters", "family", "singers", "orchestra", "group",
    ]

    private static func matches(_ variants: Set<String>, _ said: String, _ threshold: Double) -> Bool {
        variants.contains { bestWindowScore($0, said) >= threshold }
    }

    /// Full name, or a surname alone for two-word names ("Lennon", "Leppard").
    /// A lone surname is short, so it must match more closely than a full name.
    private static func artistMatches(_ name: String, _ said: String) -> Bool {
        let all = variants(name)
        if matches(all, said, Settings.artistMatchThreshold) { return true }
        let surnames = Set(all.compactMap { v -> String? in
            let words = v.split(separator: " ").map(String.init)
            guard words.count == 2, words[1].count >= 5, !genericSurnames.contains(words[1]) else { return nil }
            return words[1]
        })
        return matches(surnames, said, max(Settings.artistMatchThreshold, 90))
    }

    /// Whether the answer names the title and/or any credited artist.
    public static func grade(_ said: String, title: String, artists: [String]) -> (title: Bool, artist: Bool) {
        let said = normalize(said)
        let gotTitle = matches(titleVariants(title), said, Settings.titleMatchThreshold)
        let gotArtist = artists.contains { artistMatches($0, said) }
        return (gotTitle, gotArtist)
    }

    /// As above, and either side of a double A-side earns the song point.
    public static func grade(_ said: String, song: Song) -> (title: Bool, artist: Bool) {
        let graded = song.answerTitles.map { grade(said, title: $0, artists: song.artists) }
        return (graded.contains { $0.title }, graded[0].artist)
    }

    private static func isOneOf(_ said: String, _ phrases: [String], threshold: Double = 85) -> Bool {
        let said = normalize(said)
        let squashed = said.replacingOccurrences(of: " ", with: "")
        return phrases.contains {
            ratio(said, $0) >= threshold || squashed == $0.replacingOccurrences(of: " ", with: "")
        }
    }

    public static func isExit(_ said: String) -> Bool { isOneOf(said, exitPhrases) }
    public static func isSkip(_ said: String) -> Bool { isOneOf(said, skipPhrases) }
    public static func isRepeat(_ said: String) -> Bool { isOneOf(said, repeatPhrases) }

    public static func parsePlayerCount(_ said: String) -> Int? {
        for word in normalize(said).split(separator: " ").map(String.init) {
            if let n = playerCountWords[word] { return n }
            if word.allSatisfy(\.isASCII), let n = Int(word) { return n }
        }
        return nil
    }

    public static func categoryAliases(_ category: String, extra: [String]) -> Set<String> {
        Set([normalize(category.replacingOccurrences(of: "_", with: " "))] + extra.map(normalize))
    }

    /// Pick the category whose aliases best match what was said.
    public static func parseCategory(_ said: String, aliases: [(category: String, names: Set<String>)]) -> String? {
        let said = normalize(said)
        var best: String?
        var bestScore = 0.0
        for (category, names) in aliases {
            for name in names {
                let score = bestWindowScore(name, said)
                if score > bestScore {
                    best = category
                    bestScore = score
                }
            }
        }
        return bestScore >= Settings.categoryMatchThreshold ? best : nil
    }
}
