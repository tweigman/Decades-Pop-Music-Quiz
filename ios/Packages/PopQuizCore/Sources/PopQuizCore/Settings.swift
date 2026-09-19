// Pop Quiz rules and tunable numbers. Mirrors custom_components/popquiz/const.py;
// keep the two in step so the iPhone and Home Assistant games play the same.

public enum Difficulty: String, Sendable, CaseIterable {
    case easy, harder, difficult
}

public enum Settings {
    /// Length of each song clip, in seconds. The start point is random but
    /// always leaves room for the full clip to play.
    public static let clipSeconds = 8.0

    /// Difficulty comes from the song's best Billboard Hot 100 peak:
    /// 1...easyMaxPeak is easy, up to harderMaxPeak is harder, above is
    /// difficult. Songs with no chart peak count as difficult.
    public static let easyMaxPeak = 5
    public static let harderMaxPeak = 15

    /// One entry per round: difficulty and points per correct answer.
    /// Naming both the song and the artist earns double.
    public static let rounds: [(level: Difficulty, points: Int)] = [
        (.easy, 10),
        (.easy, 10),
        (.easy, 10),
        (.harder, 20),
        (.difficult, 40),
    ]

    /// The round (1-based) announced as the bonus round, with the intro sound.
    public static let bonusRound = 5

    public static let minPlayers = 1
    public static let maxPlayers = 6

    /// How closely an answer must match, 0-100. Lower is more forgiving.
    public static let titleMatchThreshold = 85.0
    public static let artistMatchThreshold = 80.0
    /// Names this short (in letters) must be said exactly, since fuzzy
    /// matching on very short strings produces false positives.
    public static let shortNameLength = 4
    /// How closely a spoken category name must match.
    public static let categoryMatchThreshold = 75.0

    /// Extra things a player might say for a category, beyond its file name,
    /// in chronological order (which is also the menu order).
    public static let categoryAliases: [(category: String, aliases: [String])] = [
        ("sixties", ["60s", "1960s"]),
        ("seventies", ["70s", "1970s"]),
        ("eighties", ["80s", "1980s"]),
        ("nineties", ["90s", "1990s"]),
        ("two_thousands", ["2000s", "two thousand", "the aughts", "noughties"]),
        ("twenty_tens", ["2010s", "twenty ten", "the tens"]),
        ("twenty_twenties", ["2020s", "twenty twenty"]),
    ]

    public static func aliases(for category: String) -> [String] {
        categoryAliases.first { $0.category == category }?.aliases ?? []
    }
}
