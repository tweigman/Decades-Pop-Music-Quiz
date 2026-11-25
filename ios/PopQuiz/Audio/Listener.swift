import AVFoundation
import Speech

/// Hands-free answers: on-device speech recognition that ends on its own once
/// the player stops talking.
final class Listener {
    /// How long a pause ends an answer.
    static let endOfSpeechSilence = Duration.seconds(1.2)
    /// Give up if nobody says anything for this long.
    static let noSpeechTimeout = Duration.seconds(8)
    static let maxAnswer = Duration.seconds(20)

    private let engine = AVAudioEngine()
    private let tap = AudioTap()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var session: ListenSession?

    /// The custom vocabulary model, once prepared (see Vocabulary).
    var languageModel: SFSpeechLanguageModel.Configuration?
    /// Phrases to favour when there's no custom model (e.g. in the simulator).
    var contextualStrings: [String] = []

    var onDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    /// Whether answers can be heard at all. Speech never leaves the phone, so
    /// an iPhone that can't recognize speech on the device gets typed games.
    /// (The simulator has no on-device models; debug builds there use Apple's
    /// servers instead.)
    var canListen: Bool {
        #if targetEnvironment(simulator)
        recognizer != nil
        #else
        onDevice
        #endif
    }

    /// Start the microphone. It stays on for the whole game; audio only reaches
    /// the recognizer while `listen` is running.
    func start() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap.block())
        engine.prepare()
        try engine.start()
        Diagnostics.log("mic started: \(format.sampleRate) Hz, \(format.channelCount) ch, route \(Self.route())")
    }

    func stop() {
        session?.finish()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Listen for one answer. Returns what was heard, or "" if nothing was.
    func listen(onPartial: @escaping (String) -> Void) async -> String {
        guard canListen, let recognizer, recognizer.isAvailable else {
            Diagnostics.log("recognizer unavailable")
            return ""
        }
        // iOS stops the engine when the audio configuration changes (speech
        // and clips playing can do that), so restart it if needed.
        if !engine.isRunning {
            Diagnostics.log("mic engine had stopped; restarting")
            do { try start() } catch { Diagnostics.log("mic restart failed: \(error)") }
        }

        let useModel = languageModel != nil && recognizer.supportsOnDeviceRecognition
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            if useModel { request.customizedLanguageModel = languageModel }
        }
        if !useModel { request.contextualStrings = contextualStrings }

        let session = ListenSession(onPartial: onPartial)
        self.session = session
        tap.begin(request)
        let task = recognizer.recognitionTask(with: request, resultHandler: session.handler())
        defer {
            let (buffers, peak) = tap.end()
            request.endAudio()
            task.cancel()
            Diagnostics.log(
                "listened: heard \"\(session.text)\", \(buffers) mic buffers, peak level \(String(format: "%.3f", peak)), "
                    + "custom model \(useModel), engine running \(engine.isRunning)"
                    + (session.error.map { ", error: \($0)" } ?? ""))
        }

        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled && !session.finished {
            try? await Task.sleep(for: .milliseconds(100))
            let now = clock.now
            if session.text.isEmpty ? now - start > Self.noSpeechTimeout
                : now - session.lastChange > Self.endOfSpeechSilence { break }
            if now - start > Self.maxAnswer { break }
        }
        // A recognizer that fails at once with the custom model would fail
        // every time; drop the model and use standard recognition from now on.
        if useModel, session.error != nil, session.text.isEmpty, clock.now - start < .seconds(2) {
            Diagnostics.log("custom model failed; switching to standard recognition")
            languageModel = nil
        }
        return Task.isCancelled ? "" : session.text
    }

    /// End the current answer now (the player tapped "Done").
    func finishNow() { session?.finish() }

    private static func route() -> String {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map(\.portName).joined(separator: "+")
        let outputs = route.outputs.map(\.portName).joined(separator: "+")
        return "in [\(inputs)] out [\(outputs)]"
    }
}

/// One answer's worth of recognition results.
private final class ListenSession {
    private(set) var text = ""
    private(set) var lastChange = ContinuousClock.now
    private(set) var finished = false
    private(set) var error: String?
    private let onPartial: (String) -> Void

    init(onPartial: @escaping (String) -> Void) { self.onPartial = onPartial }

    func finish() { finished = true }

    private func update(_ newText: String?, isFinal: Bool, error: String?) {
        guard !finished else { return }
        if let newText, newText != text {
            text = newText
            lastChange = .now
            onPartial(newText)
        }
        if let error { self.error = error }
        if isFinal || error != nil { finished = true }
    }

    /// The recognizer calls back on its own queue; hop to the main actor.
    nonisolated func handler() -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let message = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code): \($0.localizedDescription)" }
            Task { @MainActor in self?.update(text, isFinal: isFinal, error: message) }
        }
    }
}

/// Passes microphone buffers from the audio thread to the active request,
/// counting them and tracking the loudest sample for diagnostics.
private nonisolated final class AudioTap: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var buffers = 0
    private var peak: Float = 0

    func begin(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.withLock {
            self.request = request
            buffers = 0
            peak = 0
        }
    }

    func end() -> (buffers: Int, peak: Float) {
        lock.withLock {
            request = nil
            return (buffers, peak)
        }
    }

    func block() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in
            lock.withLock {
                guard let request else { return }
                request.append(buffer)
                buffers += 1
                if let samples = buffer.floatChannelData?[0] {
                    for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
                }
            }
        }
    }
}
