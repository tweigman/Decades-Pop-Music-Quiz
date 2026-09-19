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

func song(_ title: String, _ artists: String..., peak: Int? = 1, length: Double = 30) -> Song {
    Song(title: title, artists: artists, peak: peak, file: "\(title).mp3", previewURL: nil, length: length)
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
        ])
    }

    func newGame(_ players: Int, announceScores: Bool = false) -> (Game<SplitMix64>, Reply) {
        let game = Game(library: Self.fakeLibrary(), rng: SplitMix64(state: 1), announceScoresBeforeBonus: announceScores)
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
        let game = Game(library: Self.fakeLibrary(), rng: SystemRandomNumberGenerator())
        _ = game.start()
        #expect(game.handle("nine").speech.contains("from 1 to 6"))
        #expect(game.handle("two").speech.contains("Pick a category"))
    }

    @Test func replaceClipPicksAnotherSong() {
        let (game, reply) = newGame(1)
        let replacement = game.replaceClip()!
        #expect(replacement.song != reply.clip!.song)
        #expect(replacement.song.difficulty == .easy)
    }
}

@Suite struct RealLibraryTests {
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../..").standardized

    @Test(.enabled(if: FileManager.default.fileExists(atPath: repo.appending(path: "previews/index.csv").path)))
    func loadsEveryCategory() throws {
        let lib = try Library(dataDir: Self.repo)
        let stems = try FileManager.default.contentsOfDirectory(atPath: Self.repo.appending(path: "categories").path)
            .filter { $0.hasSuffix(".csv") }.map { String($0.dropLast(4)) }
        #expect(Set(lib.order) == Set(stems))
        #expect(Array(lib.order.prefix(7)) == Settings.categoryAliases.map(\.category))
        #expect(lib.allSongs.count > 1500)
        for name in lib.order {
            #expect(lib.songs(name, .easy).count >= 18, "\(name)")
        }
        #expect(lib.allSongs.allSatisfy { $0.previewURL != nil })
    }
}
