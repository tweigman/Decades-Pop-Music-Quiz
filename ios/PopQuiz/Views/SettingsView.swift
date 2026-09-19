import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(Quiz.self) private var quiz
    @Environment(\.dismiss) private var dismiss
    @State private var preview = AVSpeechSynthesizer()

    var body: some View {
        @Bindable var quiz = quiz
        NavigationStack {
            Form {
                Section {
                    Picker("Clips", selection: $quiz.clipSource) {
                        ForEach(ClipSource.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(!GameData.hasBundledClips)
                } header: {
                    Text("Song clips")
                } footer: {
                    Text(GameData.hasBundledClips
                        ? "Clips are built into this copy of the app. Streaming fetches each one from its public preview URL instead."
                        : "This build doesn't include the clips, so each one streams from its public preview URL.")
                }

                Section {
                    Picker("Voice", selection: $quiz.voiceIdentifier) {
                        Text("Best available").tag("")
                        ForEach(Speaker.englishVoices(), id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language)\(Self.quality(voice)))").tag(voice.identifier)
                        }
                    }
                    Button("Hear it") {
                        let line = AVSpeechUtterance(string: "Welcome to Pop Quiz! Here's your song.")
                        line.voice = AVSpeechSynthesisVoice(identifier: quiz.voiceIdentifier) ?? Speaker.bestVoice()
                        preview.stopSpeaking(at: .immediate)
                        preview.speak(line)
                    }
                } header: {
                    Text("Quizmaster")
                } footer: {
                    Text("For a more natural voice, download an Enhanced or Premium one in Settings › Accessibility › Spoken Content › Voices.")
                }

                Section {
                    Toggle("Read scores before the bonus round", isOn: $quiz.announceScoresBeforeBonus)
                } footer: {
                    Text("Multiplayer games only. Applies from the next game.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private static func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: ", Premium"
        case .enhanced: ", Enhanced"
        default: ""
        }
    }
}
