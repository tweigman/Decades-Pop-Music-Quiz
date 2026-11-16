import SwiftUI

struct HomeView: View {
    @Environment(Quiz.self) private var quiz
    @State private var showSettings = false
    @State private var starting = false

    var body: some View {
        ZStack {
            StageBackground()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "music.mic")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.neon, .gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Pop Quiz")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Name the song, the artist, or both.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()

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
                .buttonStyle(.borderedProminent)
                .tint(.neon)
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
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
            .padding(24)
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
