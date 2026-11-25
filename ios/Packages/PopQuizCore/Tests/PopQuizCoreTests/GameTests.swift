// Ports of tests/test_game.py.

import Foundation
import Testing
@testable import PopQuizCore

/// Deterministic generator so games are repeatable.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A test song. With no `vocals` it counts as sung from start to finish.
func song(
    _ title: String, _ artists: String..., peak: Int? = 1, length: Double = 30,
    level: Difficulty? = nil, vocals: [ClosedRange<Double>]? = nil
) -> Song {
    Song(title: title, artists: artists, peak: peak, length: length, levelOverride: level, vocals: vocals)
}

@Suite struct DifficultyTests {
    @Test func derivedFromPeakByDefault() {
        #expect(song("a", peak: 1).difficulty == .easy)
        #expect(song("b", peak: 12).difficulty == .harder)
        #expect(song("c", peak: 50).difficulty == .difficult)
        #expect(song("d", peak: nil).difficulty == .difficult)
    }

    /// Needed for categories where chart position is a poor proxy.
    @Test func overrideWinsOverPeak() {
        #expect(song("e", peak: nil, level: .easy).difficulty == .easy)
        #expect(song("f", peak: 1, level: .difficult).difficulty == .difficult)
    }
}

@Suite struct HolidaySeasonTests {
    func date(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func windowWrapsTheNewYear() {
        for (month, day, want) in [
            (11, 19, false), (11, 20, true), (12, 25, true),
            (1, 6, true), (1, 7, false), (9, 20, false),
        ] {
            #expect(Settings.inHolidaySeason(date(month, day)) == want, "\(month)/\(day)")
        }
    }
}

@Suite struct GradingTests {
    func grade(_ said: String, _ s: Song) -> [Bool] {
        let g = Grading.grade(said, song: s)
        return [g.title, g.artist]
    }

    @Test func bothPartsAnyOrder() {
        let s = song("Imagine", "John Lennon")
        for said in ["Imagine, by John Lennon.", "John Lennon, Imagine", "I think it's Imagine by Lennon", "imagine john lenin"] {
            #expect(grade(said, s) == [true, true], "\(said)")
        }
    }

    @Test func onePart() {
        let s = song("Imagine", "John Lennon")
        #expect(grade("Imagine by the Beatles", s) == [true, false])
        #expect(grade("It's John Lennon", s) == [false, true])
        #expect(grade("Imagination", s) == [false, false])
    }

    @Test func anyCreditedArtist() {
        let s = song("Under Pressure", "Queen", "David Bowie")
        #expect(grade("david bowie", s) == [false, true])
        #expect(grade("Under Pressure, Queen", s) == [true, true])
    }

    @Test func parenthesesAndLeadingThe() {
        let s = song("(Don't Fear) The Reaper", "Blue Öyster Cult")
        #expect(grade("Don't fear the reaper", s)[0])
        #expect(grade("the reaper by blue oyster cult", s) == [true, true])
        #expect(grade("Beatles", song("Help!", "The Beatles"))[1])
    }

    @Test func eitherSideOfTheBrackets() {
        let s = song("(Sweet Sweet Baby) Since You've Been Gone", "Aretha Franklin")
        for said in ["Sweet sweet baby", "Since you've been gone", "sweet sweet baby since you've been gone"] {
            #expect(grade(said, s)[0], "\(said)")
        }
        // A label in brackets isn't a name for the song.
        #expect(!grade("part one", song("Sky Pilot (Part One)", "The Animals"))[0])
        #expect(!grade("batman and robin", song("Look Into My Eyes (From \"Batman & Robin\")", "Bone Thugs-N-Harmony"))[0])
        #expect(grade("Volare", song("Nel Blu Dipinto Di Blu (Volaré)", "Domenico Modugno"))[0])
    }

    @Test func aMissingShortWordStillCounts() {
        #expect(grade("Her Town", song("Her Town Too", "James Taylor"))[0])
    }

    @Test func leadArtistWithoutTheBackingGroup() {
        let s = Song(id: "1", title: "Hard Headed Woman",
                     artists: ArtistCredit.parse("Elvis Presley With The Jordanaires").names, peak: 1, length: 30)
        #expect(grade("Elvis Presley", s)[1])
        #expect(grade("Presley", s)[1])
        #expect(grade("Elvis", s)[1] == false)
    }

    @Test func shortNamesNeedExactMatch() {
        let s = song("Hey", "U2")
        #expect(grade("U2", s) == [false, true])
        #expect(grade("hey you too", s) == [true, false])
        #expect(grade("they", s) == [false, false])
    }

    @Test func numbersAndSymbols() {
        #expect(grade("seven rings", song("7 rings", "Ariana Grande"))[0])
        #expect(grade("pink", song("So What", "P!nk"))[1])
    }

    @Test func commands() {
        #expect(Grading.isExit("Exit game now."))
        #expect(Grading.isSkip("Skip."))
        #expect(Grading.isRepeat("Repeat!"))
        #expect(Grading.isRepeat("play it again"))
        #expect(!Grading.isSkip("Pass the Dutchie"))
        #expect(!Grading.isExit("End Game by Taylor Swift"))
    }

    @Test func playerCount() {
        #expect(Grading.parsePlayerCount("Three.") == 3)
        #expect(Grading.parsePlayerCount("3 players") == 3)
        #expect(Grading.parsePlayerCount("Just me") == 1)
        #expect(Grading.parsePlayerCount("lots") == nil)
    }
}

@Suite struct GameTests {
    static func fakeLibrary() -> Library {
        Library(categories: [
            "eighties": (0..<20).map { song("Easy \($0)", "Artist", peak: 2) }
                + (0..<10).map { song("Harder \($0)", "Artist", peak: 10) }
                + (0..<5).map { song("Hard \($0)", "Artist", peak: 50, length: 4) }
                + (0..<5).map { song("Unranked \($0)", "Artist", peak: nil, length: 4) },
            "nineties": [song("Other", "Artist")],
            "holiday": [song("Jingle Bells", "Artist", peak: nil, level: .easy)],
        ])
    }

    func newGame(_ players: Int, announceScores: Bool = false) -> (Game<SplitMix64>, Reply) {
        let game = Game(
            library: Self.fakeLibrary(), rng: SplitMix64(state: 1),
            announceScoresBeforeBonus: announceScores, showHoliday: false)
        #expect(game.start().speech.contains("How many players"))
        _ = game.handle("\(players)")
        let reply = game.handle("eighties")
        #expect(reply.speech.contains("Eighties it is"))
        return (game, reply)
    }

    @Test func fullTwoPlayerGame() {
        var (game, reply) = newGame(2)
        var levels: [String] = []
        var titles = Set<String>()
        for round in 0..<Settings.rounds.count {
            for player in 0..<2 {
                let clip = reply.clip!
                #expect(clip.offset + clip.duration <= clip.song.length)
                #expect(!titles.contains(clip.song.title))
                titles.insert(clip.song.title)
                levels.append(String(clip.song.title.split(separator: " ")[0]).replacingOccurrences(of: "Unranked", with: "Hard"))
                let isBonus = round == 4 && player == 0
                #expect(!reply.bonusSpeech.isEmpty == isBonus)
                if isBonus {
                    // Feedback on the last answer comes before the bonus sound,
                    // the bonus announcement after it.
                    #expect(reply.speech.contains("That was"))
                    #expect(!reply.speech.contains("bonus round"))
                    #expect(reply.bonusSpeech.contains("It's the bonus round"))
                    #expect(reply.bonusSpeech.contains("Player 1, get ready"))
                    #expect(!reply.speech.contains("Scores so far"))
                }
                // Player 1 names both, player 2 names the artist only.
                reply = game.handle(player == 0 ? "\(clip.song.title) by Artist" : "Artist")
            }
        }
        #expect(levels == Array(repeating: "Easy", count: 6) + ["Harder", "Harder", "Hard", "Hard"])
        #expect(game.scores == [180, 90])
        #expect(reply.done)
        #expect(reply.speech.contains("Player 1 wins with 180 points"))
    }

    @Test func scoresBeforeBonusWhenEnabled() {
        var (game, reply) = newGame(2, announceScores: true)
        for _ in 0..<8 { reply = game.handle("skip") }
        #expect(reply.speech.contains("Scores so far: Player 1, 0, Player 2, 0."))
        #expect(reply.bonusSpeech.contains("bonus round"))
    }

    @Test func shortClipFits() {
        var (game, reply) = newGame(1)
        for _ in 0..<4 { reply = game.handle("skip") }
        #expect(reply.clip!.duration == min(Settings.clipSeconds, 4))
        #expect(reply.clip!.offset + reply.clip!.duration <= 4)
    }

    @Test func repeatSkipAndExit() {
        let (game, reply) = newGame(1)
        let first = reply.clip
        #expect(game.handle("repeat").clip == first)
        #expect(game.round == 0)
        let skipped = game.handle("skip")
        #expect(skipped.speech.contains("Skipped"))
        #expect(skipped.result?.skipped == true)
        #expect(game.scores == [0])
        #expect(game.round == 1)
        #expect(game.handle("exit game now").done)
    }

    @Test func tie() {
        var (game, reply) = newGame(2)
        for _ in 0..<10 { reply = game.handle(reply.clip!.song.title) }
        #expect(reply.speech.contains("tie between Player 1 and Player 2"))
    }

    @Test func badPlayerCountReprompts() {
        let game = Game(
            library: Self.fakeLibrary(), rng: SystemRandomNumberGenerator(), showHoliday: false)
        _ = game.start()
        #expect(game.handle("nine").speech.contains("from 1 to 6"))
        #expect(game.handle("two").speech.contains("Pick a category"))
    }

    func holidayGame(_ showHoliday: Bool) -> (Game<SplitMix64>, String) {
        let game = Game(
            library: Self.fakeLibrary(), rng: SplitMix64(state: 1), showHoliday: showHoliday)
        _ = game.start()
        return (game, game.handle("one").speech)
    }

    @Test func holidayHiddenOutOfSeason() {
        let (game, prompt) = holidayGame(false)
        #expect(!game.categories.contains("holiday"))
        #expect(prompt.contains("Pick a category for Pop Quiz, like 70s, 80s, or 2020s."))
        #expect(!prompt.contains("Holiday"))
        // Asking for it anyway gets the prompt again, not a holiday game.
        #expect(game.handle("holiday").speech.contains("didn't catch that"))
        #expect(game.category == "")
        // Nor can a button reach it.
        #expect(game.choose(category: "holiday").speech.contains("Pick a category"))
        #expect(game.category == "")
    }

    @Test func holidayOfferedInSeason() {
        let (game, prompt) = holidayGame(true)
        #expect(game.categories.contains("holiday"))
        #expect(prompt.contains("2020s, or choose Holiday!"))
        #expect(game.handle("christmas").speech.contains("Holiday it is"))
        #expect(game.category == "holiday")
    }

    @Test func replaceClipPicksAnotherSong() {
        let (game, reply) = newGame(1)
        let replacement = game.replaceClip()!
        #expect(replacement.song != reply.clip!.song)
        #expect(replacement.song.difficulty == .easy)
    }
}

@Suite struct RealLibraryTests {
    static let categories = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../../altcategories").standardized
    static let present = FileManager.default.fileExists(atPath: categories.appending(path: "eighties.csv").path)

    @Test(.enabled(if: present))
    func loadsEveryCategory() throws {
        let lib = try Library(categoriesDir: Self.categories)
        // Known categories, in the order Settings lists them; working files
        // such as _lyrics.csv are not categories.
        #expect(lib.order == Settings.categoryAliases.map(\.category))
        // Only rows Apple matched with confidence, minus repeats of a track.
        #expect(lib.allSongs.count == 7862)
        #expect(lib.categories["eighties"]?.count == 1368)
        #expect(lib.categories["fifties"]?.count == 191)
        #expect(lib.allSongs.allSatisfy { $0.previewURL != nil && $0.storeURL != nil && !$0.artists.isEmpty })
        #expect(lib.allSongs.allSatisfy { $0.storeURL!.host() == "music.apple.com" })
        // The only complaints are holiday's four repeated tracks.
        #expect(lib.warnings.count == 4, "\(lib.warnings)")
        #expect(lib.warnings.allSatisfy { $0.hasPrefix("holiday.csv") && $0.contains("repeats") })
    }

    /// Every category can supply each kind of round without falling back.
    @Test(.enabled(if: present))
    func everyCategoryCanFillEveryRound() throws {
        let lib = try Library(categoriesDir: Self.categories)
        for (name, songs) in lib.categories {
            let easy = songs.filter { $0.difficulty == .easy && $0.canLyric }
            let lesser = songs.filter { $0.difficulty == .harder && $0.canLyric }
            let obscure = songs.filter { $0.difficulty == .difficult || $0.isSparse }
            // Three easy rounds for six players is 18 songs.
            #expect(easy.count >= 18, "\(name) easy \(easy.count)")
            #expect(lesser.count >= 6, "\(name) lesser \(lesser.count)")
            #expect(obscure.count >= 6, "\(name) obscure \(obscure.count)")
            #expect(songs.contains { $0.difficulty == .easy && $0.canInstrumental }, "\(name)")
        }
    }

    /// Holiday keeps its hand-set Difficulty column; blanks fall to the peak.
    @Test(.enabled(if: present))
    func holidayUsesTheDifficultyColumn() throws {
        let lib = try Library(categoriesDir: Self.categories)
        let holiday = try #require(lib.categories["holiday"])
        #expect(holiday.count == 199)
        #expect(holiday.filter { $0.levelOverride != nil }.count == 134)
        #expect(holiday.filter { $0.difficulty == .easy }.count == 54)
        #expect(holiday.filter { $0.difficulty == .harder }.count == 62)
        #expect(holiday.filter { $0.difficulty == .difficult }.count == 83)
    }

    /// A row read end to end: timings, links and the tidied credit.
    @Test(.enabled(if: present))
    func readsTimingsAndCredits() throws {
        let lib = try Library(categoriesDir: Self.categories)
        let eighties = try #require(lib.categories["eighties"])
        let radio = try #require(eighties.first { $0.title == "On The Radio" })
        #expect(radio.id == "1599084331")
        #expect(radio.vocals == [0.0...6.2, 9.4...13.1, 16.7...21.6, 24.2...28.1])
        #expect(radio.vocalShare == 0.62)
        #expect(radio.lyricsStart == 0)
        #expect(radio.storeURL?.absoluteString.contains("music.apple.com/us/album/on-the-radio") == true)

        let islands = try #require(eighties.first { $0.title == "Islands In The Stream" })
        #expect(islands.credit == "Kenny Rogers and Dolly Parton")
        #expect(islands.artists.contains("Kenny Rogers") && islands.artists.contains("Dolly Parton"))
        #expect(Grading.grade("islands in the stream by dolly parton", song: islands) == (true, true))
    }
}

@Suite struct ArtistCreditTests {
    func names(_ credit: String) -> [String] { ArtistCredit.parse(credit).names }
    func display(_ credit: String) -> String { ArtistCredit.parse(credit).display }

    @Test func plainNamesPassThrough() {
        #expect(names("Donna Summer") == ["Donna Summer"])
        #expect(display("Donna Summer") == "Donna Summer")
        #expect(names("") == [])
    }

    @Test func guestsAreSplitOut() {
        #expect(names("Quincy Jones Featuring James Ingram") == ["Quincy Jones", "James Ingram"])
        #expect(names("Kenny Rogers Duet With Dolly Parton") == ["Kenny Rogers", "Dolly Parton"])
        #expect(names("Patti Austin A Duet With James Ingram") == ["Patti Austin", "James Ingram"])
        #expect(names("Dan Hill (Duet With Vonda Shepard)") == ["Dan Hill", "Vonda Shepard"])
        #expect(names("Bryan Adams/Rod Stewart/Sting") == ["Bryan Adams", "Rod Stewart", "Sting"])
        #expect(names("Gucci Mane X Bruno Mars X Kodak Black") == ["Gucci Mane", "Bruno Mars", "Kodak Black"])
        #expect(names("Kygo x Selena Gomez") == ["Kygo", "Selena Gomez"])
        #expect(names("Gwen Stefani; Blake Shelton") == ["Gwen Stefani", "Blake Shelton"])
    }

    @Test func anXInANameIsNotASeparator() {
        #expect(names("Lil Nas X Featuring Billy Ray Cyrus") == ["Lil Nas X", "Billy Ray Cyrus"])
        #expect(names("Lil Nas X & Jack Harlow") == ["Lil Nas X & Jack Harlow", "Lil Nas X", "Jack Harlow"])
        #expect(names("AC/DC") == ["AC/DC"])
    }

    @Test func actsWithAmpersandsStayWhole() {
        for act in ["Earth, Wind & Fire", "Simon & Garfunkel", "Crosby, Stills & Nash", "Hall & Oates",
            "Grover Washington, Jr.", "Lipps, Inc.", "Was (Not Was)"] {
            #expect(names(act) == [act], "\(act)")
        }
    }

    @Test func twoFullNamesAreTwoPeople() {
        #expect(names("Andy Gibb & Olivia Newton-John")
            == ["Andy Gibb & Olivia Newton-John", "Andy Gibb", "Olivia Newton-John"])
        #expect(names("Paul McCartney And Michael Jackson").contains("Michael Jackson"))
    }

    @Test func aLeaderAndTheirBand() {
        #expect(names("Prince And The Revolution") == ["Prince And The Revolution", "Prince", "The Revolution"])
        #expect(names("Tom Petty And The Heartbreakers").contains("Tom Petty"))
        #expect(names("Bill Haley And His Comets") == ["Bill Haley And His Comets", "Bill Haley"])
        #expect(names("Stevie Nicks With Tom Petty And The Heartbreakers")
            == ["Stevie Nicks", "Tom Petty And The Heartbreakers", "Tom Petty", "The Heartbreakers"])
    }

    @Test func displayReadsNaturally() {
        #expect(display("Kenny Rogers Duet With Dolly Parton") == "Kenny Rogers and Dolly Parton")
        #expect(display("Quincy Jones Featuring James Ingram") == "Quincy Jones featuring James Ingram")
        #expect(display("Kenny G. (Vocal By Lenny Williams)") == "Kenny G. featuring Lenny Williams")
        #expect(display("Earth, Wind & Fire") == "Earth, Wind and Fire")
        #expect(display("Selena Gomez X Marshmello") == "Selena Gomez and Marshmello")
    }

    @Test func anyCreditedNameEarnsThePoint() {
        let s = Song(
            title: "Purple Rain", credit: "Prince and The Revolution",
            artists: ArtistCredit.parse("Prince And The Revolution").names, peak: 2, length: 30)
        #expect(Grading.grade("prince", song: s) == (false, true))
        #expect(Grading.grade("purple rain by the revolution", song: s) == (true, true))
        #expect(Grading.grade("purple rain by queen", song: s) == (true, false))
    }
}

@Suite struct ClipTests {
    /// Sung for the first 12 seconds, silent after: both kinds of clip exist.
    let half = song("Half", "A", vocals: [0...12])
    let instrumental = song("Tune", "A", vocals: [])
    let bursts = song("Bursts", "A", vocals: [2...3.5, 10...11.5, 20...22])

    @Test func lyricClipsSitOnTheSinging() {
        #expect(half.canLyric)
        // 6 of the 8 seconds must be sung, so the clip starts by 6s.
        #expect(half.lyricOffsets.min() == 0 && half.lyricOffsets.max() == 6)
    }

    @Test func instrumentalClipsAvoidTheSinging() {
        #expect(half.canInstrumental)
        // At most a second of singing, so no earlier than 11s.
        #expect(half.instrumentalOffsets.min() == 11 && half.instrumentalOffsets.max() == 22)
    }

    @Test func aSongSungThroughoutHasNoInstrumentalClip() {
        let sung = song("Sung", "A")
        #expect(sung.canLyric && !sung.canInstrumental && !sung.isSparse)
    }

    @Test func instrumentalsAndBurstsAreSparse() {
        #expect(instrumental.isSparse && !instrumental.canLyric && instrumental.canInstrumental)
        #expect(instrumental.vocalShare == 0 && instrumental.lyricsStart == nil)
        // Short bursts only: some singing, but nowhere a lyrics clip could go.
        #expect(bursts.lyricsStart == nil && bursts.isSparse && !bursts.canLyric)
    }

    @Test func eitherSideOfADoubleASideCounts() {
        let s = song("Human Touch/Better Days", "Bruce Springsteen")
        #expect(Grading.grade("better days", song: s).title)
        #expect(Grading.grade("human touch", song: s).title)
        #expect(s.spokenTitle == "Human Touch and Better Days")
        // A slash inside a short title isn't a double A-side.
        #expect(song("7/11", "Beyonce").answerTitles == ["7/11"])
    }
}

@Suite struct RoundTests {
    /// Top hits and lesser hits, half of each with an instrumental stretch,
    /// plus obscure songs and a top-five instrumental.
    static func library() -> Library {
        var songs: [Song] = []
        for i in 0..<30 {
            let vocals: [ClosedRange<Double>]? = i % 2 == 0 ? [0...12] : nil
            songs.append(song("Top \(i)", "A", peak: 1 + i % 5, vocals: vocals))
            songs.append(song("Mid \(i)", "A", peak: 6 + i % 10, vocals: vocals))
            songs.append(song("Low \(i)", "A", peak: 16 + i % 5, vocals: vocals))
        }
        songs.append(song("Theme", "A", peak: 1, vocals: []))
        return Library(categories: ["eighties": songs])
    }

    /// Plays whole one-player games and returns every clip with its round.
    func clips(games: Int) -> [(round: Int, clip: Clip)] {
        var out: [(Int, Clip)] = []
        for seed in 0..<UInt64(games) {
            let game = Game(library: Self.library(), rng: SplitMix64(state: seed), showHoliday: false)
            _ = game.start()
            _ = game.handle("one")
            var reply = game.handle("eighties")
            while let clip = reply.clip {
                out.append((game.round, clip))
                reply = game.handle("skip")
            }
            #expect(game.played.count == Settings.rounds.count)
        }
        return out
    }

    func sung(_ clip: Clip) -> Double {
        clip.song.vocals.reduce(0) {
            $0 + max(0, min($1.upperBound, clip.offset + clip.duration) - max($1.lowerBound, clip.offset))
        }
    }

    @Test func easyRoundsAreTopHitsWithLyrics() {
        for (round, clip) in clips(games: 40) where round < 3 {
            #expect(clip.song.difficulty == .easy, "\(clip.song.title)")
            #expect(clip.kind == .lyrics)
            #expect(sung(clip) >= Settings.lyricSeconds)
        }
    }

    @Test func mediumRoundIsALesserHitOrATopHitWithoutVocals() {
        var lesser = 0, instrumental = 0
        for (round, clip) in clips(games: 60) where round == 3 {
            switch clip.kind {
            case .lyrics:
                #expect(clip.song.difficulty == .harder)
                #expect(sung(clip) >= Settings.lyricSeconds)
                lesser += 1
            case .instrumental:
                #expect(clip.song.difficulty == .easy)
                #expect(sung(clip) <= Settings.instrumentalSeconds)
                instrumental += 1
            default:
                Issue.record("unexpected \(clip.kind) clip in the medium round")
            }
        }
        // A coin flip: both turn up, neither dominates.
        #expect(lesser >= 15 && instrumental >= 15, "\(lesser) lesser, \(instrumental) instrumental")
    }

    @Test func hardRoundIsObscureOrSparse() {
        var kinds = Set<Clip.Kind>()
        for (round, clip) in clips(games: 80) where round == 4 {
            #expect(clip.song.difficulty == .difficult || clip.song.isSparse, "\(clip.song.title)")
            // A sparse song plays its quietest stretch; a lesser hit, anywhere.
            #expect(clip.kind == (clip.song.isSparse ? .quiet : .anywhere))
            kinds.insert(clip.kind)
        }
        #expect(kinds == [.quiet, .anywhere])
    }

    @Test func aFailedClipIsNotCredited() {
        let game = Game(library: Self.library(), rng: SplitMix64(state: 7), showHoliday: false)
        _ = game.start()
        _ = game.handle("one")
        let first = game.handle("eighties").clip!
        let second = game.replaceClip()!
        #expect(game.played == [second.song])
        #expect(second.song != first.song && second.kind == .lyrics)
    }
}
