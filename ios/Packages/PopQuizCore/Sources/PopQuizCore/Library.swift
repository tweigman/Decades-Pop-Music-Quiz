// Loads the song library from the category CSVs and the preview index.
// Mirrors custom_components/popquiz/data.py, except that a song only needs its
// preview length to be playable: the audio can come from the app bundle or be
// streamed from its preview URL.

import Foundation

public struct Song: Hashable, Sendable {
    public let title: String
    public let artists: [String]
    public let peak: Int?  // nil when the song never matched a Hot 100 entry
    /// From the CSV's Difficulty column. Empty means "derive from peak",
    /// which is what every decade category does.
    public let levelOverride: Difficulty?
    public let file: String  // MP3 file name, unique per song
    public let previewURL: URL?
    public let length: Double  // seconds of audio in the preview

    public init(
        title: String, artists: [String], peak: Int?, file: String, previewURL: URL?,
        length: Double, levelOverride: Difficulty? = nil
    ) {
        self.title = title
        self.artists = artists
        self.peak = peak
        self.levelOverride = levelOverride
        self.file = file
        self.previewURL = previewURL
        self.length = length
    }

    public var artistDisplay: String { artists.joined(separator: " and ") }

    /// easy / harder / difficult — the override if set, else from the peak.
    public var difficulty: Difficulty {
        if let levelOverride { return levelOverride }
        guard let peak else { return .difficult }
        if peak <= Settings.easyMaxPeak { return .easy }
        if peak <= Settings.harderMaxPeak { return .harder }
        return .difficult
    }
}

public struct Library: Sendable {
    /// Category names in menu order: known decades chronologically, then the rest.
    public let order: [String]
    public let categories: [String: [Song]]
    /// Rows with an unreadable Difficulty value, for the log.
    public private(set) var warnings: [String] = []

    public init(categories: [String: [Song]]) {
        let known = Settings.categoryAliases.map(\.category)
        self.categories = categories
        self.order = categories.keys.sorted {
            (known.firstIndex(of: $0) ?? known.count, $0) < (known.firstIndex(of: $1) ?? known.count, $1)
        }
    }

    /// Reads `categories/*.csv` and `previews/index.csv` under `dataDir`.
    public init(dataDir: URL) throws {
        let lengths = try Self.loadLengths(dataDir.appending(path: "previews/index.csv"))
        let csvs = try FileManager.default
            .contentsOfDirectory(at: dataDir.appending(path: "categories"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" }
        var categories = [String: [Song]]()
        var warnings = [String]()
        for url in csvs {
            let (songs, problems) = try Self.loadCategory(url, lengths: lengths)
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

    private static func loadLengths(_ url: URL) throws -> [String: Double] {
        var lengths = [String: Double]()
        for row in try CSV.rows(url) {
            guard let file = row["File"], let seconds = row["Preview (s)"].flatMap(Double.init) else { continue }
            lengths[(file as NSString).lastPathComponent] = seconds
        }
        return lengths
    }

    private static func loadCategory(
        _ url: URL, lengths: [String: Double]
    ) throws -> (songs: [Song], warnings: [String]) {
        var warnings = [String]()
        let songs = try CSV.rows(url).compactMap { row -> Song? in
            let file = row["MP3 File", default: ""].trimmed
            guard !file.isEmpty, let length = lengths[file] else { return nil }
            let clean = row["Clean Title", default: ""].trimmed
            let peak = row["Peak (Hot 100)", default: ""].trimmed
            // Blank means "derive from the chart peak"; an unreadable value
            // says so and falls back to the peak rather than failing the load.
            let level = row["Difficulty", default: ""].trimmed.lowercased()
            let levelOverride = level.isEmpty ? nil : Difficulty(rawValue: level)
            if !level.isEmpty && levelOverride == nil {
                warnings.append(
                    "\(url.lastPathComponent) row \(row["#", default: "?"]) has Difficulty "
                        + "'\(level)'; expected easy/harder/difficult or blank — using the chart peak")
            }
            return Song(
                title: clean.isEmpty ? row["Title", default: ""].trimmed : clean,
                artists: row["Artist(s)", default: ""].split(separator: ";").map { String($0).trimmed }
                    .filter { !$0.isEmpty },
                peak: Double(peak).map { Int($0) },
                file: file,
                previewURL: URL(string: row["Preview URL", default: ""].trimmed),
                length: length,
                levelOverride: levelOverride
            )
        }
        return (songs, warnings)
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
