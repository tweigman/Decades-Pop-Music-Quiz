// Checks the Swift grader against decisions recorded from the Python one.
// Regenerate the fixture after changing grading.py:
//   python3 ios/scripts/make_grading_fixtures.py

import Foundation
import Testing
@testable import PopQuizCore

struct Fixture: Decodable {
    struct Grade: Decodable { let said: String; let title: String; let artists: [String]; let got: [Bool] }
    struct Normalized: Decodable { let `in`: String; let out: String }
    struct Ratio: Decodable { let a: String; let b: String; let ratio: Double }
    struct Command: Decodable { let said: String; let exit: Bool; let skip: Bool; let `repeat`: Bool }
    struct Count: Decodable { let said: String; let count: Int? }
    struct Category: Decodable { let said: String; let category: String? }

    let grades: [Grade]
    let normalize: [Normalized]
    let ratios: [Ratio]
    let commands: [Command]
    let counts: [Count]
    let categories: [Category]

    static let shared: Fixture = {
        let url = Bundle.module.url(forResource: "Fixtures/grading", withExtension: "json")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()
}

@Suite struct GradingParityTests {
    let fixture = Fixture.shared

    @Test func normalizeMatchesPython() {
        let wrong = fixture.normalize.filter { Grading.normalize($0.in) != $0.out }
        #expect(wrong.isEmpty, "\(wrong.prefix(10).map { "\($0.in) -> \(Grading.normalize($0.in)), want \($0.out)" })")
    }

    @Test func ratioMatchesDifflibExactly() {
        let wrong = fixture.ratios.filter { Grading.ratio($0.a, $0.b) != $0.ratio }
        #expect(wrong.isEmpty, "\(wrong.prefix(5).map { "\($0.a) | \($0.b): \(Grading.ratio($0.a, $0.b)) vs \($0.ratio)" })")
    }

    @Test func gradesMatchPython() {
        let wrong = fixture.grades.filter {
            let got = Grading.grade($0.said, title: $0.title, artists: $0.artists)
            return [got.title, got.artist] != $0.got
        }
        #expect(fixture.grades.count > 10_000)
        #expect(wrong.isEmpty, "\(wrong.count) differ, e.g. \(wrong.prefix(10).map { "'\($0.said)' vs \($0.title)/\($0.artists) want \($0.got)" })")
    }

    @Test func commandsMatchPython() {
        for c in fixture.commands {
            #expect(Grading.isExit(c.said) == c.exit, "\(c.said)")
            #expect(Grading.isSkip(c.said) == c.skip, "\(c.said)")
            #expect(Grading.isRepeat(c.said) == c.repeat, "\(c.said)")
        }
    }

    @Test func playerCountsMatchPython() {
        for c in fixture.counts {
            #expect(Grading.parsePlayerCount(c.said) == c.count, "\(c.said)")
        }
    }

    @Test func categoriesMatchPython() {
        let aliases = Settings.categoryAliases.map {
            ($0.category, Grading.categoryAliases($0.category, extra: $0.aliases))
        }
        for c in fixture.categories {
            #expect(Grading.parseCategory(c.said, aliases: aliases) == c.category, "\(c.said)")
        }
    }
}
