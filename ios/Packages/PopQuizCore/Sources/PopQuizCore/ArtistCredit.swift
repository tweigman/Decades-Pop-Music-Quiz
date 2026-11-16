// Turns a chart credit such as "Kenny Rogers Duet With Dolly Parton" into the
// names a player might say, and a tidier line for the quizmaster to read.
//
// The charts credit artists every which way: "Featuring", "With", "&", "X",
// slashes, brackets. A player who names anyone on the record has earned the
// point, so the credit is split into people. Splitting is cautious about "&",
// "And" and commas, because those are just as often part of one act's name:
// "Earth, Wind & Fire" and "Simon & Garfunkel" stay whole.

import Foundation

public enum ArtistCredit {
    /// `names`: every name that should earn the artist point.
    /// `display`: the credit as shown and spoken.
    public static func parse(_ credit: String) -> (names: [String], display: String) {
        var text = credit.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return ([], "") }
        // "Dan Hill (Duet With Vonda Shepard)" -> "Dan Hill Duet With Vonda Shepard"
        text = replace(bracketedGuest, in: text, with: " $1")

        // Split on the words that always join separate acts.
        var parts: [String] = []
        var joins: [String] = []
        var rest = text.startIndex
        let whole = NSRange(text.startIndex..., in: text)
        for match in strong.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[rest..<range.lowerBound]))
            joins.append(joinWord(for: String(text[range])))
            rest = range.upperBound
        }
        parts.append(String(text[rest...]))
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }

        var names: [String] = []
        func add(_ name: String) {
            let name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        for part in parts where !part.isEmpty {
            add(part)
            if let band = backingBand.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) {
                // "Prince And The Revolution": Prince alone is a fair answer,
                // and so is The Revolution.
                add(group(1, of: band, in: part))
                if group(2, of: band, in: part).lowercased() == "the" {
                    add("The " + group(3, of: band, in: part))
                }
            } else {
                // "Andy Gibb & Olivia Newton-John" is two people, but only
                // split when every piece looks like a full name, which leaves
                // "Hall & Oates" and "Crosby, Stills & Nash" alone.
                let pieces = split(soft, part)
                if pieces.count > 1, pieces.allSatisfy({ $0.split(separator: " ").count >= 2 }) {
                    pieces.forEach(add)
                }
            }
        }

        var display = ""
        for (i, part) in parts.enumerated() where !part.isEmpty {
            if !display.isEmpty { display += " \(joins[i - 1]) " }
            display += part
        }
        display = replace(ampersandOrAnd, in: display, with: " and ")
        return (names, display)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let bracketedGuest = regex(
        #"\s*\((?=(?:A\s+)?(?:Duet\s+With|With|Featuring|Feat\.?|Ft\.?|Vocals?\s+By|Introducing|(?:Co-)?Starring)\b)([^)]*)\)"#)

    /// A slash only separates acts when there's a word on both sides ("AC/DC" doesn't).
    private static let strong = regex(
        #"\s*;\s*"#
            + #"|\s+(?:A\s+)?Duet\s+With\s+"#
            + #"|\s+(?:&\s+)?(?:Featuring|Feat\.?|Ft\.?)\s+"#
            + #"|\s+With\s+"#
            + #"|\s+(?:Co-)?Starring\s+"#
            + #"|\s+(?:&\s+)?Introducing\s+"#
            + #"|\s+Vocals?\s+By\s+"#
            // "Selena Gomez X Marshmello", but not the X in "Lil Nas X Featuring…"
            + #"|\s+x\s+(?![&,]|(?:Featuring|Feat|Ft|With|And|Duet|Introducing|Starring)\b)"#
            + #"|(?<=[^/\s]{3})/(?=[^/\s]{3})"#)

    private static let backingBand = regex(#"^(.+?)\s+(?:&|And)\s+(The|His|Her|Their)\s+(.+)$"#)
    private static let soft = regex(#"\s*,\s*|\s+&\s+|\s+And\s+|\s+\+\s+"#)
    private static let ampersandOrAnd = regex(#"\s+(?:&|And)\s+"#)

    private static func joinWord(for separator: String) -> String {
        let word = separator.lowercased()
        if word.contains("feat") || word.contains("ft") || word.contains("vocal") { return "featuring" }
        if word.contains("introducing") { return "introducing" }
        if word.contains("starring") { return "starring" }
        return "and"
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func group(_ n: Int, of match: NSTextCheckingResult, in text: String) -> String {
        Range(match.range(at: n), in: text).map { String(text[$0]) } ?? ""
    }

    private static func split(_ regex: NSRegularExpression, _ text: String) -> [String] {
        var pieces: [String] = []
        var rest = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            pieces.append(String(text[rest..<range.lowerBound]))
            rest = range.upperBound
        }
        pieces.append(String(text[rest...]))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
