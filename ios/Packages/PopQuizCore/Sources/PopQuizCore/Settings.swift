// Pop Quiz rules and tunable numbers. The scoring, rounds and match thresholds
// mirror custom_components/popquiz/const.py. The clip rules below (lyrics,
// instrumental, sparse) are the iPhone app's own: Home Assistant still plays
// the Spotify lists, which have no vocal timings.

import Foundation

public enum Difficulty: String, Sendable, CaseIterable {
    case easy, harder, difficult
}

public enum Settings {
    /// Length of each song clip, in seconds. The start point is random but
    /// always leaves room for the full clip to play.
    public static let clipSeconds = 8.0

    /// How finely clip start points are tried along a preview, in seconds.
    public static let clipStep = 0.25

    /// A "lyrics" clip holds at least this much singing (of clipSeconds).
    /// Easy rounds always play one.
    public static let lyricSeconds = 6.0
    /// A lyrics clip starts this much earlier than its chosen window (and
    /// plays this much longer), so the singing never begins on the very first
    /// beat of the clip.
    public static let lyricLeadIn = 0.5
    /// An "instrumental" clip holds at most this much singing.
    public static let instrumentalSeconds = 1.0
    /// A song sung for less than this share of its preview is hard to place,
    /// whatever its chart position, and belongs in the difficult round.
    public static let sparseVocalShare = 0.40

    /// How well known a song is comes from its best Billboard Hot 100 peak:
    /// 1...easyMaxPeak is easy, up to harderMaxPeak is harder, above is
    /// difficult. Songs with no chart peak count as difficult.
    ///
    /// A round then pairs that with a kind of clip:
    ///   easy       a top hit, played where the singing is
    ///   harder     a coin flip: a lesser hit where the singing is, or a top
    ///              hit from an instrumental stretch
    ///   difficult  a lesser hit from anywhere in the preview, or any song
    ///              with little singing, from its quietest stretch
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
    public static let titleMatchThreshold = 80.0
    public static let artistMatchThreshold = 80.0
    /// Names this short (in letters) must be said exactly, since fuzzy
    /// matching on very short strings produces false positives.
    public static let shortNameLength = 4
    /// How closely a spoken category name must match.
    public static let categoryMatchThreshold = 75.0

    /// Extra things a player might say for a category, beyond its file name,
    /// in chronological order (which is also the menu order).
    public static let categoryAliases: [(category: String, aliases: [String])] = [
        ("fifties", ["50s", "1950s"]),
        ("sixties", ["60s", "1960s"]),
        ("seventies", ["70s", "1970s"]),
        ("eighties", ["80s", "1980s"]),
        ("nineties", ["90s", "1990s"]),
        ("two_thousands", ["2000s", "two thousand", "the aughts", "noughties"]),
        ("twenty_tens", ["2010s", "twenty ten", "the tens"]),
        ("twenty_twenties", ["2020s", "twenty twenty"]),
        ("holiday", ["holidays", "christmas", "xmas", "christmas music", "holiday music"]),
    ]

    /// The holiday category is seasonal: it is offered only between these two
    /// dates, inclusive, which wrap around the new year. The "extended
    /// playlists" setting offers it whatever the date.
    public static let holidayCategory = "holiday"
    public static let holidayFrom = (11, 20)
    public static let holidayUntil = (1, 6)

    /// Whether `date` falls inside the holiday window.
    public static func inHolidaySeason(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        return (month, day) >= holidayFrom || (month, day) <= holidayUntil
    }

    public static func aliases(for category: String) -> [String] {
        categoryAliases.first { $0.category == category }?.aliases ?? []
    }
}
