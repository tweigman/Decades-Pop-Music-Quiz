import SwiftUI

@main
struct PopQuizApp: App {
    @State private var quiz = Quiz()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if quiz.isPlaying || quiz.phase == .over {
                    GameView()
                } else {
                    HomeView()
                }
            }
            .environment(quiz)
            .task {
                await quiz.load()
                if Quiz.demo { await quiz.start() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { quiz.pause() }
            }
        }
    }
}

extension Color {
    static let stage = Color(red: 0.07, green: 0.05, blue: 0.16)
    static let neon = Color(red: 1.0, green: 0.27, blue: 0.6)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.2)
    static let cyanGlow = Color(red: 0.3, green: 0.85, blue: 1.0)
}

struct StageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.16, green: 0.06, blue: 0.3), .stage, .black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
