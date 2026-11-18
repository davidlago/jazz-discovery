import Foundation

/// A listening guide (guides.json): one recording, its form as a run of sections, and a note for each that names
/// something you can hear. Prose is written by hand; the times come from someone listening, with the Mac's guide
/// editor, and are only true for the Apple Music recording they were taken from (`songID`, `duration`).
struct Guide: Codable, Identifiable, Hashable {
    let id: String
    /// The recording, as "artist|title" in tracks.json.
    let track: String
    /// The Apple Music song the times were taken from, and its length in seconds. Nil until it's been timed.
    var songID: Int? = nil
    var duration: Double? = nil
    var album: String? = nil
    var tune: String? = nil
    /// Why this recording is worth the attention, and its form in a line ("AABA, 32 bars; two choruses each").
    let intro: String
    let form: String
    var sections: [GuideSection]
    /// Where the facts came from (not shown).
    var source: String? = nil

    /// Every section has a time, in order, and the recording's length is known.
    var isTimed: Bool {
        guard let duration, duration > 0, !sections.isEmpty, sections.allSatisfy({ $0.at != nil }) else { return false }
        let times = sections.compactMap(\.at)
        return zip(times, times.dropFirst()).allSatisfy { $0 <= $1 } && (times.last ?? 0) < duration
    }

    /// The section playing at `seconds`: the last one that has started. Before the first one starts, the first.
    func section(at seconds: Double) -> Int? {
        guard isTimed else { return nil }
        let times = sections.compactMap(\.at)
        return times.lastIndex { $0 <= seconds } ?? 0
    }

    /// Where a section starts and ends, in seconds (the last one ends with the recording).
    func span(of index: Int) -> ClosedRange<Double>? {
        guard isTimed, let duration, sections.indices.contains(index), let start = sections[index].at else { return nil }
        let end = sections.indices.contains(index + 1) ? (sections[index + 1].at ?? duration) : duration
        return start...max(start, end)
    }

    /// Whether the times fit a recording that's playing: the very song they were taken from, or the same title and
    /// artist within two seconds of its length (another edition of the same master). A live version doesn't fit.
    func fits(songID id: Int?, title: String?, artist: String?, duration d: Double) -> Bool {
        guard isTimed, let duration else { return false }
        if let id, id == songID { return true }
        guard let title, let artist, abs(d - duration) <= 2 else { return false }
        let parts = track.split(separator: "|", maxSplits: 1).map { Guide.fold(String($0)) }
        guard parts.count == 2 else { return false }
        return Guide.fold(title) == parts[1] && Guide.fold(artist).contains(parts[0])
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct GuideSection: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case intro, head, solo, trading, ensemble, interlude, vamp, headOut = "head-out", coda

        var label: String {
            switch self {
            case .intro: return "Intro"
            case .head: return "Head"
            case .solo: return "Solo"
            case .trading: return "Trading"
            case .ensemble: return "Ensemble"
            case .interlude: return "Interlude"
            case .vamp: return "Vamp"
            case .headOut: return "Head out"
            case .coda: return "Coda"
            }
        }
    }

    /// When it starts, in seconds. Nil until timed.
    var at: Double? = nil
    var kind: Kind
    var label: String
    /// Who's out in front: artist IDs, or names for players without a page.
    var who: [String] = []
    var note: String
    /// Glossary terms the note leans on, linked under it.
    var terms: [String] = []
    /// Single moments inside the section ("the quote from …").
    var marks: [GuideMark] = []

    private enum Keys: String, CodingKey { case at, kind, label, who, note, terms, marks }

    init(at: Double? = nil, kind: Kind, label: String, who: [String] = [], note: String, terms: [String] = [], marks: [GuideMark] = []) {
        self.at = at; self.kind = kind; self.label = label; self.who = who; self.note = note; self.terms = terms; self.marks = marks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        at = try c.decodeIfPresent(Double.self, forKey: .at)
        kind = try c.decode(Kind.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        who = try c.decodeIfPresent([String].self, forKey: .who) ?? []
        note = try c.decode(String.self, forKey: .note)
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
        marks = try c.decodeIfPresent([GuideMark].self, forKey: .marks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(at, forKey: .at)
        try c.encode(kind, forKey: .kind)
        try c.encode(label, forKey: .label)
        if !who.isEmpty { try c.encode(who, forKey: .who) }
        try c.encode(note, forKey: .note)
        if !terms.isEmpty { try c.encode(terms, forKey: .terms) }
        if !marks.isEmpty { try c.encode(marks, forKey: .marks) }
    }
}

struct GuideMark: Codable, Hashable {
    var at: Double? = nil
    var note: String
}

struct GuidesData: Codable { var guides: [Guide] }

extension JazzLibrary {
    func guide(_ id: String) -> Guide? { guides.first { $0.id == id } }

    /// The guide for an Apple Music song: the one its times were taken from, or the one tracks.json resolves to.
    func guide(forSongID id: Int) -> Guide? {
        guides.first { $0.songID == id || tracks[$0.track]?.id == id }
    }

    /// The guide for a recording in tracks.json ("artist|title").
    func guide(forTrack ref: String) -> Guide? { guides.first { $0.track == ref } }

    /// The guide for what's playing, if there's one: by the song its times were taken from, by the song tracks.json
    /// resolves its recording to, or by title, artist and length.
    func guide(songID: Int?, title: String?, artist: String?, duration: Double) -> Guide? {
        if let songID {
            if let g = guides.first(where: { $0.songID == songID }) { return g }
            if let g = guides.first(where: { tracks[$0.track]?.id == songID }) { return g }
        }
        return guides.first { $0.fits(songID: nil, title: title, artist: artist, duration: duration) }
    }

    /// The name to show for someone in a guide's `who`.
    func guideName(_ who: String) -> String { artist(who)?.name ?? who }
}
