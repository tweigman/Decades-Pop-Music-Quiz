import SwiftUI

/// Who made the game, and the work it stands on.
struct AcknowledgementsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("AmbericLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 56)
                        .foregroundStyle(Color.gold)
                        .accessibilityHidden(true)
                    Text("Decades: Pop Music Quiz").font(.title2.weight(.black)).fontDesign(.rounded)
                    Text("Made by Amberic LLC").font(.subheadline).foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Music") {
                credit("Song previews",
                       "Every clip is a preview streamed from Apple Music. Each song links to the full track on Apple Music, on its result card and in the set list at the end of a game.")
                credit("Song lists",
                       "Songs are chosen from U.S. Hot 100 chart history, using the public chart archive compiled by the rwd-billboard-data project at the University of Texas at Austin.")
                credit("Vocal timings",
                       "Where the singing falls in each preview was measured ahead of time with Demucs, an open-source music separation model from Meta AI Research (MIT License).")
            }

            Section("Voice") {
                credit("Speech",
                       "The quizmaster speaks with Apple's built-in voices, and answers are recognized on this device with Apple's speech recognition. Nothing you say is recorded or kept.")
            }

            Section {
                credit("Answer matching",
                       "The fuzzy matching that forgives misheard and misspelled answers is adapted from Python's difflib module. Copyright © 2001 Python Software Foundation; All Rights Reserved. Used under the PSF License Agreement.")
                credit("Built with Claude Code",
                       "Written with Claude Code, Anthropic's AI coding assistant.")
            } header: {
                Text("Software")
            }

            Section {
                Text("Inspired by the name-that-tune games played around radios, jukeboxes and living rooms for generations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
