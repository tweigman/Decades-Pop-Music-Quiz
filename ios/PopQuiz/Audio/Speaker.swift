import AVFoundation

/// The quizmaster's voice. `say` returns when the line has been spoken, or
/// immediately when the calling task is cancelled.
@MainActor final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: CheckedContinuation<Void, Never>?
    private var current: ObjectIdentifier?  // the utterance `finished` waits on
    var voiceIdentifier: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) async {
        guard !text.isEmpty, !Task.isCancelled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.bestVoice()
        utterance.postUtteranceDelay = 0.15
        // If the synthesizer never reports back (it happens when its voices
        // fail to load), move on rather than stall the game.
        let words = Double(text.split(separator: " ").count)
        let watchdog = Task {
            try await Task.sleep(for: .seconds(words / 1.5 + 4))
            print("Speech didn't finish in time; carrying on")
            stop()
        }
        defer { watchdog.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finished = continuation
                current = ObjectIdentifier(utterance)
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resume()
    }

    private func resume() {
        finished?.resume()
        finished = nil
        current = nil
    }

    /// Callbacks arrive late, so one for an earlier, stopped line must not
    /// end the line being spoken now.
    private func ended(_ utterance: ObjectIdentifier) {
        if utterance == current { resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.ended(id) }
    }

    /// English voices, best quality first. Enhanced and Premium voices appear
    /// once downloaded in Settings > Accessibility > Spoken Content > Voices.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted {
                ($0.quality.rawValue, $0.language == "en-US" ? 1 : 0, $1.name)
                    > ($1.quality.rawValue, $1.language == "en-US" ? 1 : 0, $0.name)
            }
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        englishVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
