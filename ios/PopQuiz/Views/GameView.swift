import PopQuizCore
import SwiftUI

struct GameView: View {
    @Environment(Quiz.self) private var quiz
    @State private var typing = false
    @State private var typed = ""
    @State private var confirmQuit = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            StageBackground()
            VStack(spacing: 18) {
                header
                if !quiz.scores.isEmpty { Scoreboard() }
                Spacer(minLength: 0)
                StatusOrb(phase: quiz.phase)
                Text(quiz.caption)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 90, alignment: .top)
                    .animation(.easeInOut, value: quiz.caption)
                if !quiz.heard.isEmpty {
                    Text("“\(quiz.heard)”")
                        .font(.headline)
                        .foregroundStyle(Color.cyanGlow)
                        .multilineTextAlignment(.center)
                }
                if let result = quiz.lastResult { ResultCard(result: result) }
                Spacer(minLength: 0)
                controls
            }
            .padding(20)
        }
        .confirmationDialog("End this game?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("End game", role: .destructive) { quiz.quit() }
        }
    }

    private var header: some View {
        HStack {
            if quiz.gameState == .answer || quiz.phase == .over {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quiz.category.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline).foregroundStyle(Color.gold)
                    Text(roundLabel).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text("Pop Quiz").font(.headline).foregroundStyle(Color.gold)
            }
            Spacer()
            if quiz.phase != .over {
                Button { confirmQuit = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.title)
                }
                .tint(.white.opacity(0.6))
            }
        }
    }

    private var roundLabel: String {
        if quiz.phase == .over { return "Final scores" }
        let total = Settings.rounds.count
        let no = min(quiz.round + 1, total)
        return no == Settings.bonusRound ? "Bonus round" : "Round \(no) of \(total)"
    }

    @ViewBuilder private var controls: some View {
        if quiz.phase == .over {
            HStack(spacing: 12) {
                Button("Home") { quiz.quit() }
                    .buttonStyle(.bordered).tint(.white)
                Button("Play again") { Task { quiz.quit(); await quiz.start() } }
                    .buttonStyle(.borderedProminent).tint(.neon)
            }
            .controlSize(.large)
        } else if quiz.phase == .paused {
            Button("Resume") { quiz.resume() }
                .buttonStyle(.borderedProminent).tint(.neon).controlSize(.large)
        } else {
            switch quiz.gameState {
            case .players: playerButtons
            case .category: categoryButtons
            case .answer: answerControls
            case .over: EmptyView()
            }
        }
    }

    private var playerButtons: some View {
        HStack(spacing: 10) {
            ForEach(Settings.minPlayers...Settings.maxPlayers, id: \.self) { n in
                Button("\(n)") { quiz.say("\(n)") }
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered).tint(.white)
            }
        }
    }

    private var categoryButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(quiz.availableCategories, id: \.self) { category in
                Button {
                    quiz.choose(category: category)
                } label: {
                    Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.white).controlSize(.large)
            }
        }
    }

    @ViewBuilder private var answerControls: some View {
        VStack(spacing: 12) {
            if typing {
                HStack {
                    TextField("Song or artist", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .submitLabel(.send)
                        .onSubmit(sendTyped)
                    Button("Send", action: sendTyped).buttonStyle(.borderedProminent).tint(.neon)
                }
            }
            if quiz.phase == .listening {
                Button { quiz.doneTalking() } label: {
                    Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.neon).controlSize(.large)
            }
            HStack(spacing: 12) {
                Button { quiz.say("repeat") } label: { Label("Repeat", systemImage: "arrow.counterclockwise") }
                Button { quiz.say("skip") } label: { Label("Skip", systemImage: "forward.fill") }
                Button {
                    typing.toggle()
                    fieldFocused = typing
                } label: { Label("Type", systemImage: "keyboard") }
            }
            .buttonStyle(.bordered).tint(.white)
        }
    }

    private func sendTyped() {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        typed = ""
        typing = false
        fieldFocused = false
        quiz.say(text)
    }
}

private struct Scoreboard: View {
    @Environment(Quiz.self) private var quiz

    var body: some View {
        let top = quiz.scores.max() ?? 0
        HStack(spacing: 8) {
            ForEach(quiz.scores.indices, id: \.self) { i in
                let current = quiz.gameState == .answer && quiz.phase != .over && i == quiz.turn
                let leader = quiz.phase == .over && top > 0 && quiz.scores[i] == top
                VStack(spacing: 2) {
                    Text(quiz.scores.count == 1 ? "Score" : "P\(i + 1)")
                        .font(.caption.bold())
                    Text("\(quiz.scores[i])")
                        .font(.title3.monospacedDigit().bold())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(current || leader ? Color.stage : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(leader ? Color.gold : current ? Color.cyanGlow : .white.opacity(0.1)))
                .animation(.spring, value: quiz.scores)
            }
        }
    }
}

private struct ResultCard: View {
    let result: Reply.Result

    var body: some View {
        VStack(spacing: 6) {
            Text(result.song.title).font(.headline).foregroundStyle(.white)
            Text(result.song.artistDisplay).font(.subheadline).foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 14) {
                mark("Song", result.gotTitle)
                mark("Artist", result.gotArtist)
                Text(result.skipped ? "Skipped" : "+\(result.points)")
                    .font(.subheadline.bold())
                    .foregroundStyle(result.points > 0 ? Color.gold : .white.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)))
    }

    private func mark(_ label: String, _ got: Bool) -> some View {
        Label(label, systemImage: got ? "checkmark.circle.fill" : "xmark.circle")
            .font(.subheadline)
            .foregroundStyle(got ? .green : .white.opacity(0.5))
    }
}

private struct StatusOrb: View {
    let phase: Quiz.Phase
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 170, height: 170)
                .scaleEffect(pulse && animates ? 1.12 : 0.95)
            Circle()
                .fill(RadialGradient(colors: [color, color.opacity(0.5)], center: .center, startRadius: 5, endRadius: 70))
                .frame(width: 124, height: 124)
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: animates)
        }
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .overlay(alignment: .bottom) {
            Text(label).font(.caption.bold()).foregroundStyle(.white.opacity(0.7)).offset(y: 24)
        }
        .padding(.bottom, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var animates: Bool { [.speaking, .playing, .listening, .bonus, .loading].contains(phase) }

    private var symbol: String {
        switch phase {
        case .speaking: "waveform"
        case .bonus: "sparkles"
        case .loading: "arrow.down.circle"
        case .playing: "music.note"
        case .listening: "mic.fill"
        case .paused: "pause.fill"
        case .over: "trophy.fill"
        case .idle: "music.mic"
        }
    }

    private var label: String {
        switch phase {
        case .speaking: "Quizmaster"
        case .bonus: "Bonus round!"
        case .loading: "Loading clip"
        case .playing: "Listen…"
        case .listening: "Your answer"
        case .paused: "Paused"
        case .over: "Game over"
        case .idle: ""
        }
    }

    private var color: Color {
        switch phase {
        case .listening: .cyanGlow
        case .playing, .loading: .neon
        case .bonus, .over: .gold
        default: .purple
        }
    }
}
