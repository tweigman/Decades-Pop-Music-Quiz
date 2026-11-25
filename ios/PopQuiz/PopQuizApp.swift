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
    /// Deep green, the backdrop everything sits on.
    static let stage = Color(red: 0.04, green: 0.12, blue: 0.09)
    /// Yellow for buttons and anything to tap.
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.16)
    /// Lighter gold for highlighted text: category, points, the leader.
    static let gold = Color(red: 1.0, green: 0.85, blue: 0.42)
    /// Pale green for "your turn": the current player, what was heard.
    static let sage = Color(red: 0.62, green: 0.87, blue: 0.68)
    /// Mid green for the quizmaster speaking.
    static let pine = Color(red: 0.2, green: 0.5, blue: 0.36)
}

extension View {
    /// The main action on a screen: a yellow button with dark green text.
    func primaryButton() -> some View {
        buttonStyle(.borderedProminent).tint(.amber).foregroundStyle(Color.stage)
    }
}

struct StageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.11, green: 0.28, blue: 0.2), .stage, Color(red: 0.01, green: 0.05, blue: 0.03)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
