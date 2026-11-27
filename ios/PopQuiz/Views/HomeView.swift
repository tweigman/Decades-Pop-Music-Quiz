import SwiftUI

/// Speak or type: how this game will take its answers.
private struct AnswerModePicker: View {
    @Binding var typed: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                option("Speak answers", "mic.fill", selected: !typed) { typed = false }
                option("Type answers", "keyboard", selected: typed) { typed = true }
            }
            .padding(4)
            .background(Capsule().fill(.white.opacity(0.08)))
            Text(typed ? "The microphone stays off for this game." : "The game listens after each clip.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .animation(.easeInOut(duration: 0.2), value: typed)
    }

    private func option(_ title: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.stage : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? Color.amber : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HomeView: View {
    @Environment(Quiz.self) private var quiz
    @State private var showSettings = false
    @State private var starting = false

    var body: some View {
        ZStack {
            StageBackground()
            VStack(spacing: 28) {
                Spacer()
                Image("Artwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: Color.amber.opacity(0.35), radius: 24)
                    .accessibilityHidden(true)
                VStack(spacing: 2) {
                    Text("Decades")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("POP MUSIC QUIZ")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Color.gold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Decades: Pop Music Quiz")
                Text("Name the song, the artist, or both.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Made for a group: gather round and call out your answers. No typing needed, though you can switch to typed answers for a noisy room.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()

                if quiz.canListen {
                    AnswerModePicker(typed: Bindable(quiz).typedAnswers)
                } else {
                    Label("This device can't recognize speech on its own, so answers are typed.", systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                Button {
                    starting = true
                    Task {
                        await quiz.start()
                        starting = false
                    }
                } label: {
                    Text(starting ? "Starting…" : "Play")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .primaryButton()
                .clipShape(Capsule())
                .disabled(quiz.library == nil || starting)

                if let error = quiz.errorMessage {
                    Text(error).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
                VStack(spacing: 6) {
                    Label(quiz.vocabularyStatus, systemImage: "waveform")
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Song previews from Apple Music · Built with Claude Code")
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image("AmbericLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                            .accessibilityHidden(true)
                        Text("Amberic LLC")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Made by Amberic LLC")
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
            .padding(24)
            // On an iPad, keep a phone-like column in the middle.
            .frame(maxWidth: 560)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title2).padding()
            }
            .tint(.white.opacity(0.8))
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
