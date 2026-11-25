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

                Section {
                    Toggle("Enable extended playlists", isOn: $quiz.extendedPlaylists)
                } header: {
                    Text("Seasonal")
                } footer: {
                    Text(quiz.holidayAvailable && !quiz.extendedPlaylists
                        ? "Holiday is in season, so it's on the category list until January 6th. Turn this on to keep it there year-round."
                        : "Holiday songs appear on the category list from November 20th to January 6th. Turn this on to play them at any time of year.")
                }

                Section {
                    NavigationLink("Credits & Acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Made by", value: "Amberic LLC")
                } header: {
                    Text("About")
                } footer: {
                    Text("Clips are streamed from Apple Music's song previews, so Pop Quiz needs an internet connection. Every song you hear is listed, with a link, when the game ends.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
        .tint(.amber)
    }

    private static func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: ", Premium"
        case .enhanced: ", Enhanced"
        default: ""
        }
    }
}
