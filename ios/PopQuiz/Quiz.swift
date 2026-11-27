import AVFoundation
import Observation
import PopQuizCore
import Speech
import SwiftUI

/// Runs a game: speaks each reply, plays clips, listens for answers and feeds
/// them back to the game. The screens observe this and call its actions.
@Observable
final class Quiz {
    enum Phase: Equatable {
        case idle, speaking, bonus, loading, playing, listening, typing, paused, over
    }

    private(set) var phase = Phase.idle
    private(set) var caption = ""  // what the quizmaster last said
    private(set) var heard = ""  // live transcript of the answer
    private(set) var lastResult: Reply.Result?
    private(set) var errorMessage: String?

    private(set) var vocabularyStatus = "Preparing song names…"
    private(set) var library: Library?

    // Mirrors of the game's state, for the screen.
    private(set) var gameState = Game<SystemRandomNumberGenerator>.State.players
    private(set) var scores: [Int] = []
    private(set) var round = 0
    private(set) var turn = 0
    private(set) var category = ""
    /// The categories this game offers: the decades, plus holiday in season.
    private(set) var availableCategories: [String] = []
    /// Every song played in the game just finished, for the credits.
    private(set) var credits: [Song] = []

    // Settings, remembered between launches.
    var voiceIdentifier = UserDefaults.standard.string(forKey: "voice") ?? "" {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voice") }
    }
    var announceScoresBeforeBonus = UserDefaults.standard.bool(forKey: "announceScores") {
        didSet { UserDefaults.standard.set(announceScoresBeforeBonus, forKey: "announceScores") }
    }
    /// Answers are typed, not spoken: for a noisy room. Chosen on the home
    /// screen; a typed game never turns the microphone on.
    var typedAnswers = UserDefaults.standard.bool(forKey: "typedAnswers") {
        didSet { UserDefaults.standard.set(typedAnswers, forKey: "typedAnswers") }
    }
    /// How the game in progress takes answers, fixed when it starts.
    private(set) var typedGame = false
    /// Offer the seasonal categories whatever the date.
    var extendedPlaylists = UserDefaults.standard.bool(forKey: "extendedPlaylists") {
        didSet { UserDefaults.standard.set(extendedPlaylists, forKey: "extendedPlaylists") }
    }

    private var game: Game<SystemRandomNumberGenerator>?
    private let speaker = Speaker()
    private let clips = ClipPlayer()
    private let listener = Listener()
    private var running: Task<Void, Never>?
    private var silentTurns = 0

    var isPlaying: Bool { game != nil && phase != .over }

    /// Whether this device can take spoken answers (on-device recognition).
    var canListen: Bool { listener.canListen }

    /// Whether the holiday category is on offer, and why.
    var holidayAvailable: Bool { extendedPlaylists || Settings.inHolidaySeason() }

    // MARK: setup

    func load() async {
        guard library == nil else { return }
        Diagnostics.reset()
        let library: Library
        do {
            let dir = GameData.categoriesDir
            library = try await Task.detached { try Library(categoriesDir: dir) }.value
        } catch {
            vocabularyStatus = "Couldn't load the songs: \(error.localizedDescription)"
            return
        }
        self.library = library
        for warning in library.warnings { Diagnostics.log(warning) }
        listener.contextualStrings = Vocabulary.contextualStrings(library)
        guard listener.onDevice else {
            Diagnostics.log("on-device recognition unavailable")
            vocabularyStatus = "\(library.allSongs.count) songs · on-device recognition unavailable"
            return
        }
        do {
            let started = ContinuousClock.now
            listener.languageModel = try await Vocabulary.prepare(library)
            vocabularyStatus = "\(library.allSongs.count) songs · song names learned"
            Diagnostics.log("custom vocabulary ready after \(ContinuousClock.now - started)")
        } catch {
            // The simulator has no on-device speech models; the game still
            // works with standard recognition.
            Diagnostics.log("custom vocabulary failed: \(error)")
            vocabularyStatus = "\(library.allSongs.count) songs · standard recognition"
        }
    }

    // MARK: actions

    func start() async {
        guard let library else { return }
        errorMessage = nil
        let typed = (typedAnswers || !listener.canListen) && !Self.demo
        let allowed = Self.demo || typed ? true : await Self.requestPermissions()
        Diagnostics.log("permissions granted: \(allowed), typed game: \(typed)")
        guard allowed else {
            errorMessage = "Decades needs the microphone and speech recognition. Turn them on in Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            if typed {
                // No microphone at all: plain playback.
                try session.setCategory(.playback, mode: .default)
            } else {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            }
            try session.setActive(true)
            if !Self.demo && !typed { try listener.start() }
        } catch {
            Diagnostics.log("audio start failed: \(error)")
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        speaker.voiceIdentifier = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        let game = Game(
            library: library,
            rng: SystemRandomNumberGenerator(),
            announceScoresBeforeBonus: announceScoresBeforeBonus,
            showHoliday: holidayAvailable)
        self.game = game
        availableCategories = game.categories
        Diagnostics.log(
            "game start: extended \(extendedPlaylists), in season \(Settings.inHolidaySeason()), "
                + "categories \(game.categories.joined(separator: ","))")
        lastResult = nil
        credits = []
        silentTurns = 0
        typedGame = typed
        run(game.start(typed: typed))
    }

    /// A spoken, tapped or typed answer or command.
    func say(_ text: String) {
        guard let game, phase != .over else { return }
        run(game.handle(text))
    }

    func choose(category: String) {
        guard let game else { return }
        run(game.choose(category: category))
    }

    /// "Done": stop listening and use what's been heard so far.
    func doneTalking() { listener.finishNow() }

    /// Carry on after the game paused for lack of answers.
    func resume() { say("repeat") }

    /// Pause when the app leaves the screen; a tap on Resume carries on.
    func pause() {
        guard isPlaying else { return }
        running?.cancel()
        speaker.stop()
        clips.stop()
        phase = .paused
    }

    func quit() {
        running?.cancel()
        speaker.stop()
        clips.stop()
        listener.stop()
        game = nil
        phase = .idle
        caption = ""
        heard = ""
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: the loop

    private func run(_ reply: Reply) {
        running?.cancel()
        speaker.stop()
        clips.stop()
        running = Task { await perform(reply) }
    }

    private func perform(_ first: Reply) async {
        guard let game else { return }
        var reply = first
        while !Task.isCancelled {
            sync(game, reply)
            // Fetch the clip while the question is being read out.
            let prepared = reply.clip.map { clip in
                Task { try await clips.prepare(clip) }
            }

            phase = .speaking
            caption = reply.speech
            await speaker.say(reply.speech)
            if !reply.bonusSpeech.isEmpty {
                phase = .bonus
                if let intro = GameData.bonusIntro { await clips.playAll(intro) }
                caption = reply.bonusSpeech
                await speaker.say(reply.bonusSpeech)
            }
            if Task.isCancelled { return }
            if reply.done {
                finish(game)
                return
            }

            if let prepared {
                guard await playClip(prepared, game) else { return }
            }

            heard = ""
            if typedGame {
                // Wait for the keyboard or a button; say() carries on from here.
                phase = .typing
                return
            }
            phase = .listening
            let answer = Self.demo ? await demoAnswer(game) : await listener.listen { [weak self] in self?.heard = $0 }
            if Task.isCancelled { return }
            if answer.isEmpty {
                silentTurns += 1
                if silentTurns >= 2 {
                    phase = .paused
                    caption = "Still there? Tap Resume to hear it again."
                    return
                }
            } else {
                silentTurns = 0
            }
            reply = game.handle(answer)
        }
    }

    /// Play the current clip, swapping in another song if its audio can't be
    /// loaded. Returns false if the game should stop here.
    private func playClip(_ first: Task<PreparedClip, Error>, _ game: Game<SystemRandomNumberGenerator>) async -> Bool {
        var prepared = first
        for _ in 0..<4 {
            guard let clip = game.clip else { return false }
            phase = .loading
            do {
                let ready = try await prepared.value
                if Task.isCancelled { return false }
                phase = .playing
                try await clips.play(ready, for: clip.duration)
                return !Task.isCancelled
            } catch {
                if Task.isCancelled { return false }
                guard let next = game.replaceClip() else { return false }
                Diagnostics.log("couldn't load \(clip.song.title): \(error.localizedDescription)")
                prepared = Task { try await clips.prepare(next) }
            }
        }
        phase = .paused
        caption = "I can't load the songs. Check your internet connection, then tap Resume."
        return false
    }

    private func sync(_ game: Game<SystemRandomNumberGenerator>, _ reply: Reply) {
        gameState = game.state
        scores = game.scores
        round = game.round
        turn = game.turn
        category = game.category
        if let result = reply.result { lastResult = result }
    }

    private func finish(_ game: Game<SystemRandomNumberGenerator>) {
        credits = game.played
        phase = .over
        listener.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Launch with -demo (debug builds) to watch a game play itself: no
    /// microphone, and every answer is right.
    #if DEBUG
    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")
    #else
    static let demo = false
    #endif

    private func demoAnswer(_ game: Game<SystemRandomNumberGenerator>) async -> String {
        try? await Task.sleep(for: .seconds(1))
        let answer = switch game.state {
        case .players: "one"
        case .category: "eighties"
        default: game.clip.map { "\($0.song.title) by \($0.song.artists[0])" } ?? "skip"
        }
        heard = answer
        try? await Task.sleep(for: .seconds(1))
        return answer
    }

    private nonisolated static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }
}
