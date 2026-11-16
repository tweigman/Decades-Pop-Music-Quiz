// Loads the song library from the category CSVs (altcategories/ in the repo).
// Each row carries an Apple preview URL, an Apple Music link, and where in the
// 30-second preview the singing is, which is what lets a round ask for a clip
// with lyrics or one without.

import Foundation

public struct Song: Hashable, Sendable {
    /// Apple's track id: unique per recording, and the name of its cached clip.
    public let id: String
    public let title: String
    /// The artist credit as shown and spoken ("Kenny Rogers and Dolly Parton").
    public let credit: String
    /// Every name that earns the artist point; any one will do.
    public let artists: [String]
    public let peak: Int?  // best Hot 100 position; nil if it never charted
    /// From the CSV's Difficulty column. Empty means "derive from peak",
    /// which is what every decade category does.
    public let levelOverride: Difficulty?
    public let previewURL: URL?
    public let storeURL: URL?  // the song's page on Apple Music
    public let length: Double  // seconds of audio in the preview
    /// The stretches of the preview with singing, in order.
    public let vocals: [ClosedRange<Double>]
    /// Share of the preview with singing, 0...1.
    public let vocalShare: Double
    /// Where the first vocal stretch of 3+ seconds starts; nil when there are
    /// no vocals, or only short bursts.
    public let lyricsStart: Double?

    /// Clip start points, in seconds, where the clip is mostly singing.
    public let lyricOffsets: [Double]
    /// Clip start points where the clip has next to no singing.
    public let instrumentalOffsets: [Double]
    /// Clip start points with the least singing this preview offers.
    public let quietOffsets: [Double]

    /// `vocals: nil` means "not analysed": the whole preview counts as sung,
    /// so a list without timings still plays, with every clip a lyrics clip.
    public init(
        id: String? = nil, title: String, credit: String? = nil, artists: [String], peak: Int?,
        previewURL: URL? = nil, storeURL: URL? = nil, length: Double,
        levelOverride: Difficulty? = nil, vocals: [ClosedRange<Double>]? = nil,
        vocalShare: Double? = nil, lyricsStart: Double? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.credit = credit ?? artists.joined(separator: " and ")
        self.artists = artists
        self.peak = peak
        self.levelOverride = levelOverride
        self.previewURL = previewURL
        self.storeURL = storeURL
        self.length = length
        let vocals = vocals ?? [0...length]
        self.vocals = vocals
        self.vocalShare = vocalShare
            ?? (length > 0 ? vocals.reduce(0) { $0 + $1.upperBound - $1.lowerBound } / length : 0)
        self.lyricsStart = lyricsStart
            ?? vocals.first { $0.upperBound - $0.lowerBound >= 3 }?.lowerBound

        // Slide a clip-length window along the preview and note how much
        // singing each position holds.
        let clip = min(Settings.clipSeconds, length)
        let scale = clip / Settings.clipSeconds
        var windows: [(offset: Double, sung: Double)] = []
        var offset = 0.0
        while offset <= length - clip + 1e-9 {
            let end = offset + clip
            let sung = vocals.reduce(0) { $0 + max(0, min($1.upperBound, end) - max($1.lowerBound, offset)) }
            windows.append((offset, sung))
            offset += Settings.clipStep
        }
        let least = windows.map(\.sung).min() ?? 0
        lyricOffsets = self.lyricsStart == nil
            ? [] : windows.filter { $0.sung >= Settings.lyricSeconds * scale }.map(\.offset)
        instrumentalOffsets = windows.filter { $0.sung <= Settings.instrumentalSeconds * scale }.map(\.offset)
        quietOffsets = windows.filter { $0.sung <= least + 0.5 }.map(\.offset)
    }

    public var artistDisplay: String { credit }

    /// The title as read aloud: a double A-side's slash becomes "and".
    public var spokenTitle: String { title.replacingOccurrences(of: "/", with: " and ") }

    /// Titles that earn the song point. For a double A-side such as
    /// "Human Touch/Better Days", either side will do.
    public var answerTitles: [String] {
        let sides = title.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard sides.count > 1,
            sides.allSatisfy({ $0.filter(\.isLetter).count >= 3 })
        else { return [title] }
        return [title] + sides
    }

    /// easy / harder / difficult by fame — the override if set, else from the peak.
    public var difficulty: Difficulty {
        if let levelOverride { return levelOverride }
        guard let peak else { return .difficult }
        if peak <= Settings.easyMaxPeak { return .easy }
        if peak <= Settings.harderMaxPeak { return .harder }
        return .difficult
    }

    /// Whether a clip of mostly singing can be cut from the preview.
    public var canLyric: Bool { !lyricOffsets.isEmpty }
    /// Whether a clip with next to no singing can be cut from it.
    public var canInstrumental: Bool { !instrumentalOffsets.isEmpty }
    /// Little singing, or only short bursts of it: hard to place by ear.
    public var isSparse: Bool { vocalShare < Settings.sparseVocalShare || lyricsStart == nil }
}

public struct Library: Sendable {
    /// Category names in menu order: known decades chronologically, then the rest.
    public let order: [String]
    public let categories: [String: [Song]]
    /// Rows that were skipped or misread, for the log.
    public private(set) var warnings: [String] = []

    public init(categories: [String: [Song]]) {
        let known = Settings.categoryAliases.map(\.category)
        self.categories = categories
        self.order = categories.keys.sorted {
            (known.firstIndex(of: $0) ?? known.count, $0) < (known.firstIndex(of: $1) ?? known.count, $1)
        }
    }

    /// Reads every `*.csv` in `categoriesDir`, one category per file. Files
    /// whose names start with an underscore are working files, not categories.
    public init(categoriesDir: URL) throws {
        let csvs = try FileManager.default
            .contentsOfDirectory(at: categoriesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" && !$0.lastPathComponent.hasPrefix("_") }
        var categories = [String: [Song]]()
        var warnings = [String]()
        for url in csvs {
            let (songs, problems) = try Self.loadCategory(url)
            warnings += problems
            if !songs.isEmpty {
                categories[url.deletingPathExtension().lastPathComponent] = songs
            }
        }
        self.init(categories: categories)
        self.warnings = warnings
    }

    public func songs(_ category: String, _ level: Difficulty) -> [Song] {
        (categories[category] ?? []).filter { $0.difficulty == level }
    }

    public var allSongs: [Song] { order.flatMap { categories[$0] ?? [] } }

    private static let trackID = try! NSRegularExpression(pattern: #"[?&]i=(\d+)"#)

    private static func loadCategory(_ url: URL) throws -> (songs: [Song], warnings: [String]) {
        let name = url.lastPathComponent
        var warnings = [String]()
        var seen = Set<String>()
        let songs = try CSV.rows(url).compactMap { row -> Song? in
            func cell(_ column: String) -> String { row[column, default: ""].trimmed }
            // Only rows whose Apple match was confirmed, and that have audio.
            if let match = row["Match"], match.trimmed != "ok" { return nil }
            guard let previewURL = URL(string: cell("Preview URL")), !cell("Preview URL").isEmpty else {
                return nil
            }
            let link = cell("URL")
            let range = NSRange(link.startIndex..., in: link)
            let id = trackID.firstMatch(in: link, range: range)
                .flatMap { Range($0.range(at: 1), in: link) }.map { String(link[$0]) }
                ?? previewURL.deletingPathExtension().lastPathComponent
            guard seen.insert(id).inserted else {
                warnings.append("\(name) row \(cell("#")) repeats Apple track \(id); skipped")
                return nil
            }

            // Blank means "derive from the chart peak"; an unreadable value
            // says so and falls back to the peak rather than failing the load.
            let level = cell("Difficulty").lowercased()
            let levelOverride = level.isEmpty ? nil : Difficulty(rawValue: level)
            if !level.isEmpty && levelOverride == nil {
                warnings.append(
                    "\(name) row \(cell("#")) has Difficulty '\(level)'; "
                        + "expected easy/harder/difficult or blank — using the chart peak")
            }

            let credit = ArtistCredit.parse(cell("Artist(s)"))
            var artists = credit.names
            // Apple's name for the artist is often the plainer one.
            for extra in ArtistCredit.parse(cell("Apple Artist")).names
            where !artists.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) {
                artists.append(extra)
            }
            // No "Vocal Segments" column at all means the list wasn't analysed.
            let vocals = row["Vocal Segments"].map(Self.segments)
            return Song(
                id: id,
                title: cell("Clean Title").isEmpty ? cell("Title") : cell("Clean Title"),
                credit: credit.display,
                artists: artists,
                peak: Double(cell("Peak (Hot 100)")).map { Int($0) },
                previewURL: previewURL,
                storeURL: URL(string: link),
                length: Double(cell("Preview (s)")) ?? 30,
                levelOverride: levelOverride,
                vocals: vocals,
                vocalShare: Double(cell("Vocal %")).map { $0 / 100 },
                lyricsStart: vocals == nil ? nil : Double(cell("Lyrics Start (s)"))
            )
        }
        return (songs, warnings)
    }

    /// "0.0-6.2;9.4-13.1" -> [0.0...6.2, 9.4...13.1]
    private static func segments(_ text: String) -> [ClosedRange<Double>] {
        text.split(separator: ";").compactMap { part in
            let ends = part.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return ends.count == 2 && ends[0] <= ends[1] ? ends[0]...ends[1] : nil
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Just enough RFC 4180 to read the pipeline's CSVs (quoted fields, "" escapes).
enum CSV {
    static func rows(_ url: URL) throws -> [[String: String]] {
        let records = parse(try String(contentsOf: url, encoding: .utf8))
        guard let header = records.first else { return [] }
        return records.dropFirst().map { fields in
            Dictionary(zip(header, fields).map { ($0, $1) }, uniquingKeysWith: { a, _ in a })
        }
    }

    static func parse(_ text: String) -> [[String]] {
        var records = [[String]]()
        var record = [String]()
        var field = ""
        var quoted = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    let next = chars.next()
                    if next == "\"" { field.unicodeScalars.append(c) } else { quoted = false; pending = next }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": record.append(field); field = ""
            case "\r": continue
            case "\n":
                record.append(field); field = ""
                records.append(record); record = []
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        // Strip a UTF-8 byte-order mark from the first header, if any.
        if let first = records.first?.first, first.hasPrefix("\u{FEFF}") {
            records[0][0] = String(first.dropFirst())
        }
        return records
    }
}
