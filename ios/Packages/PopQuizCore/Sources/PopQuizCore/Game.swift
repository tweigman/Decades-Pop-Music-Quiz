// The Pop Quiz game: a state machine driven by what the player says.
// A port of custom_components/popquiz/game.py. Each call returns a Reply
// describing what to say and whether to play a clip or keep listening; the
// caller does the audio.

import Foundation

public struct Clip: Equatable, Sendable {
    public let song: Song
    public let offset: Double  // seconds into the preview
    public let duration: Double
}

public struct Reply: Equatable, Sendable {
    public var speech: String
    public var listen = false  // keep listening right after speaking
    public var clip: Clip? = nil  // after speaking, play this, then listen
    /// Bonus round only: after `speech`, play the bonus build-up sound, then
    /// say this, then play the clip.
    public var bonusSpeech = ""
    public var done = false  // the game is over
    /// The last answer's song and what it scored, for the screen.
    public var result: Result? = nil

    public struct Result: Equatable, Sendable {
        public let song: Song
        public let player: Int  // 0-based
        public let gotTitle: Bool
        public let gotArtist: Bool
        public let points: Int
        public let skipped: Bool
    }
}

public final class Game<RNG: RandomNumberGenerator> {
    public enum State { case players, category, answer, over }

    public private(set) var state = State.players
    public private(set) var players = 0
    public private(set) var category = ""
    public private(set) var scores: [Int] = []
    public private(set) var round = 0  // 0-based
    public private(set) var turn = 0  // 0-based player index
    public private(set) var clip: Clip?

    private let library: Library
    private let announceScoresBeforeBonus: Bool
    private var rng: RNG
    private let aliases: [(category: String, names: Set<String>)]
    private var prompt = ""  // the last question asked, for "repeat"
    private var used = Set<String>()

    /// When a difficulty runs out of songs, borrow from the nearest one.
    private static func fallback(_ level: Difficulty) -> [Difficulty] {
        switch level {
        case .easy: [.easy, .harder, .difficult]
        case .harder: [.harder, .easy, .difficult]
        case .difficult: [.difficult, .harder, .easy]
        }
    }

    public init(library: Library, rng: RNG, announceScoresBeforeBonus: Bool = false) {
        self.library = library
        self.rng = rng
        self.announceScoresBeforeBonus = announceScoresBeforeBonus
        self.aliases = library.order.map {
            ($0, Grading.categoryAliases($0, extra: Settings.aliases(for: $0)))
        }
    }

    // MARK: entry points

    public func start() -> Reply {
        prompt = Phrases.askPlayers
        return Reply(speech: Phrases.welcome + Phrases.askPlayers, listen: true)
    }

    public func handle(_ said: String) -> Reply {
        if Grading.isExit(said) {
            state = .over
            return Reply(speech: "Game over. Thanks for playing Pop Quiz!", done: true)
        }
        switch state {
        case .players: return onPlayers(said)
        case .category: return onCategory(said)
        case .answer: return onAnswer(said)
        case .over: return Reply(speech: "The game is over.", done: true)
        }
    }

    /// Swap the current clip for another song of the same difficulty, e.g.
    /// when its audio can't be loaded. The unplayable song isn't picked again.
    public func replaceClip() -> Clip? {
        guard state == .answer else { return nil }
        clip = pickClip(Settings.rounds[round].level)
        return clip
    }

    // MARK: setup

    private func onPlayers(_ said: String) -> Reply {
        if Grading.isRepeat(said) { return Reply(speech: prompt, listen: true) }
        guard let count = Grading.parsePlayerCount(said),
            (Settings.minPlayers...Settings.maxPlayers).contains(count)
        else {
            return Reply(
                speech: "Please say a number from \(Settings.minPlayers) to \(Settings.maxPlayers). How many players?",
                listen: true)
        }
        players = count
        scores = Array(repeating: 0, count: count)
        state = .category
        prompt = categoryPrompt()
        let who = count == 1 ? "One player." : "\(count) players."
        return Reply(speech: "\(who) \(prompt)", listen: true)
    }

    private func categoryPrompt() -> String {
        let names = library.order.map { $0.replacingOccurrences(of: "_", with: " ") }
        let listed = names.count > 1
            ? names.dropLast().joined(separator: ", ") + ", or \(names.last!)"
            : names.first ?? ""
        return "Pick a category: \(listed)."
    }

    private func onCategory(_ said: String) -> Reply {
        if Grading.isRepeat(said) { return Reply(speech: prompt, listen: true) }
        guard let category = Grading.parseCategory(said, aliases: aliases) else {
            return Reply(speech: "Sorry, I didn't catch that. \(prompt)", listen: true)
        }
        return choose(category: category)
    }

    /// Pick the category directly (the category buttons on screen).
    public func choose(category: String) -> Reply {
        guard state == .category, library.categories[category] != nil else {
            return Reply(speech: prompt, listen: true)
        }
        self.category = category
        state = .answer
        return ask(lead: "\(category.replacingOccurrences(of: "_", with: " ").capitalizedFirst) it is!")
    }

    // MARK: play

    private func onAnswer(_ said: String) -> Reply {
        guard let clip else { return Reply(speech: "The game is over.", done: true) }
        if Grading.isRepeat(said) { return Reply(speech: "Here it is again.", clip: clip) }
        let song = clip.song
        let reveal = "That was \(song.title), by \(song.artistDisplay)."
        if Grading.isSkip(said) {
            let result = Reply.Result(
                song: song, player: turn, gotTitle: false, gotArtist: false, points: 0, skipped: true)
            return advance(feedback: "Skipped. \(reveal)", result: result)
        }
        if Grading.normalize(said).isEmpty {
            return Reply(speech: "I didn't catch that. Say your answer, repeat, or skip.", listen: true)
        }
        let got = Grading.grade(said, song: song)
        let points = Settings.rounds[round].points * ((got.title ? 1 : 0) + (got.artist ? 1 : 0))
        scores[turn] += points
        let verdict = switch (got.title, got.artist) {
        case (true, true): "You got both! \(points) points."
        case (true, false): "You got the song! \(points) points."
        case (false, true): "You got the artist! \(points) points."
        case (false, false): "Sorry, no points."
        }
        let result = Reply.Result(
            song: song, player: turn, gotTitle: got.title, gotArtist: got.artist, points: points, skipped: false)
        return advance(feedback: "\(verdict) \(reveal)", result: result)
    }

    private func advance(feedback: String, result: Reply.Result) -> Reply {
        turn += 1
        if turn == players {
            turn = 0
            round += 1
        }
        var reply = round == Settings.rounds.count ? finish(feedback: feedback) : ask(lead: feedback)
        reply.result = result
        return reply
    }

    /// Announce the next turn and pick its clip.
    private func ask(lead: String) -> Reply {
        let roundNo = round + 1
        let (level, points) = Settings.rounds[round]
        var parts = [lead]
        let newRound = turn == 0
        if newRound && roundNo == Settings.bonusRound {
            if announceScoresBeforeBonus && players > 1 {
                parts.append("Scores so far: \(scoreList()).")
            }
            clip = pickClip(level)
            let getReady = players > 1 ? "Player 1, get ready." : "Get ready."
            return Reply(
                speech: parts.joined(separator: " "),
                clip: clip,
                bonusSpeech: "It's the bonus round! Every answer is worth \(points) points, "
                    + "\(points * 2) if you get both. \(getReady)")
        }
        if newRound && roundNo > 1 && points != Settings.rounds[round - 1].points {
            parts.append("Round \(roundNo). The points go up: \(points) per answer, \(points * 2) for both.")
        } else if newRound {
            parts.append("Round \(roundNo).")
        }
        parts.append(players > 1 ? "Player \(turn + 1), here's your song." : "Here's your song.")
        clip = pickClip(level)
        return Reply(speech: parts.joined(separator: " "), clip: clip)
    }

    private func pickClip(_ level: Difficulty) -> Clip {
        var pool: [Song] = []
        for lvl in Self.fallback(level) {
            pool = library.songs(category, lvl).filter { !used.contains($0.file) }
            if !pool.isEmpty { break }
        }
        if pool.isEmpty {
            // Every song in the category has been played; allow repeats.
            used.removeAll()
            pool = library.categories[category] ?? []
        }
        let song = pool.randomElement(using: &rng)!
        used.insert(song.file)
        let duration = min(Settings.clipSeconds, song.length)
        let offset = Double.random(in: 0...(song.length - duration), using: &rng)
        return Clip(song: song, offset: (offset * 100).rounded() / 100, duration: duration)
    }

    // MARK: ending

    private func scoreList() -> String {
        scores.enumerated().map { "Player \($0 + 1), \($1)" }.joined(separator: ", ")
    }

    private func finish(feedback: String) -> Reply {
        state = .over
        var parts = [feedback, "That's the game!"]
        let top = scores.max() ?? 0
        if players == 1 {
            parts.append("You scored \(top) points.")
        } else {
            parts.append("Final scores: \(scoreList()).")
        }
        if top == 0 {
            parts.append("Better luck next game!")
            return Reply(speech: parts.joined(separator: " "), done: true)
        }
        let winners = scores.enumerated().filter { $1 == top }.map { "Player \($0.offset + 1)" }
        if winners.count > 1 {
            parts.append(
                "It's a tie between \(winners.dropLast().joined(separator: ", ")) and \(winners.last!), "
                    + "with \(top) points each!")
        } else if players > 1 {
            parts.append("\(winners[0]) wins with \(top) points!")
        }
        parts.append(Phrases.celebrations.randomElement(using: &rng)!)
        return Reply(speech: parts.joined(separator: " "), done: true)
    }
}

extension String {
    /// Python's str.capitalize(): first letter upper, the rest lower.
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst().lowercased() }
}
