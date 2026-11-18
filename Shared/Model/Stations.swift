import SwiftUI

/// A named track resolved ahead of time to its Apple Music song (tracks.json), tied back to the guide.
struct StationTrack: Decodable, Hashable, Identifiable {
    /// "artist|title", as `TrackRef.id`.
    var ref: String = ""
    let track: CatalogTrack
    /// The Crate album it's on, if any.
    let album: String?
    let era: String?
    let year: Int?
    /// Kept out of the Blindfold Test (a clip that starts on nothing recognisable, a doubtful match).
    let skip: Bool

    var id: Int { track.trackId }
    var artistName: String { String(ref.split(separator: "|").first ?? Substring(track.artistName)) }
    /// The title in the ref ("artist|title", or "artist|title|year" for a Songbook version).
    var title: String { ref.split(separator: "|").dropFirst().first.map(String.init) ?? track.name }

    private enum Keys: String, CodingKey { case album, era, year, skip }

    init(from decoder: Decoder) throws {
        track = try CatalogTrack(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        era = try c.decodeIfPresent(String.self, forKey: .era)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        skip = try c.decodeIfPresent(Bool.self, forKey: .skip) ?? false
    }

    init(ref: String, track: CatalogTrack, album: String?, era: String?, year: Int?, skip: Bool = false) {
        self.ref = ref; self.track = track; self.album = album; self.era = era; self.year = year; self.skip = skip
    }

    /// Loads tracks.json, setting each track's ref from its key.
    static func load(_ map: [String: StationTrack]) -> [String: StationTrack] {
        Dictionary(uniqueKeysWithValues: map.map { k, v in var t = v; t.ref = k; return (k, t) })
    }
}

/// A station: an endless, explained mix from part of the guide.
struct Station: Identifiable, Hashable {
    enum Kind: Hashable { case era(String), decade(Int), instrument(String), longWay, newToYou, tune(String), songbook, lineage(String),
                          place(String), label(String) }
    let kind: Kind
    let title: String
    let subtitle: String
    let color: String

    var tint: Color { Color(hex: color) }
    var id: String {
        switch kind {
        case .era(let e): return "era-\(e)"
        case .decade(let d): return "decade-\(d)"
        case .instrument(let i): return "instrument-\(i)"
        case .longWay: return "long-way"
        case .newToYou: return "new-to-you"
        case .tune(let t): return "tune-\(t)"
        case .songbook: return "songbook"
        case .lineage(let l): return "lineage-\(l)"
        case .place(let p): return "place-\(p)"
        case .label(let l): return "label-\(l)"
        }
    }
}

/// Picks and orders a station's tracks, and says why each one is there.
enum Programmer {
    /// A station needs this many tracks to be offered.
    static let minimumTracks = 12
    /// Instruments with stations, and their titles.
    static let instruments: [(family: String, title: String)] = [
        ("saxophone", "Saxophones"), ("trumpet", "Trumpets & Cornets"), ("piano", "Piano"), ("bass", "Bass"),
        ("drums", "Drums"), ("guitar", "Guitar"), ("vocals", "Voices"), ("trombone", "Trombone"),
        ("organ", "Organ"), ("vibraphone", "Vibes"), ("clarinet", "Clarinet"), ("flute", "Flute"),
    ]

    /// Every station with enough to play: The Long Way and New to You first, then eras, decades and instruments.
    static func stations(library: JazzLibrary, includeNewToYou: Bool = false) -> [Station] {
        var out = [Station(kind: .longWay, title: "The Long Way", subtitle: "130 years in order, from ragtime to now",
                           color: "#E9B949")]
        if includeNewToYou {
            out.append(Station(kind: .newToYou, title: "New to You", subtitle: "Records you haven't heard yet",
                               color: "#F3EDE2"))
        }
        for era in library.eras {
            out.append(Station(kind: .era(era.id), title: "\(era.stamp ?? era.name) Radio", subtitle: era.tagline,
                               color: era.color))
        }
        for d in library.decades {
            let tint = library.eras.first { $0.start <= d + 5 && $0.end >= d + 5 }?.color ?? "#E9B949"
            out.append(Station(kind: .decade(d), title: "The \(String(d))s", subtitle: "\(String(d)) to \(String(d + 9))",
                               color: tint))
        }
        for (f, title) in instruments {
            out.append(Station(kind: .instrument(f), title: title, subtitle: "Across every era", color: "#A69E91"))
        }
        if !library.tunes.isEmpty {
            out.append(Station(kind: .songbook, title: "The Songbook", subtitle: "Versions of the standards, shuffled",
                               color: "#E9D8B4"))
        }
        return out.filter { s in s.kind == .newToYou || pool(for: s, library: library, isHeard: { _ in false }).count >= minimumTracks }
    }

    static func station(id: String, library: JazzLibrary, includeNewToYou: Bool = true) -> Station? {
        // A place's or label's station is worked out alone: pages ask for theirs each time they draw.
        if id.hasPrefix("place-") { return placeStation(String(id.dropFirst(6)), library: library) }
        if id.hasPrefix("label-") { return labelStation(String(id.dropFirst(6)), library: library) }
        return stations(library: library, includeNewToYou: includeNewToYou).first { $0.id == id }
    }

    /// A station for a city, club or studio (what was recorded there, and who played there) or a label, played from
    /// its page; not on the Radio page, which would get long. Needs fewer tracks than the main stations.
    static func placeAndLabelStations(library: JazzLibrary) -> [Station] {
        library.places.compactMap { placeStation($0.id, library: library) } + library.labels.compactMap { labelStation($0.id, library: library) }
    }

    static func placeStation(_ id: String, library: JazzLibrary) -> Station? {
        guard let p = library.place(id) else { return nil }
        let s = Station(kind: .place(p.id), title: "\(p.name) Radio", subtitle: p.years,
                        color: p.eras.first.flatMap { library.era($0)?.color } ?? "#E9B949")
        return pool(for: s, library: library, isHeard: { _ in false }).count >= minimumPlaceTracks ? s : nil
    }

    static func labelStation(_ id: String, library: JazzLibrary) -> Station? {
        guard let l = library.label(id) else { return nil }
        let s = Station(kind: .label(l.id), title: "\(l.name) Radio", subtitle: "Since \(String(l.founded))", color: l.color)
        return pool(for: s, library: library, isHeard: { _ in false }).count >= minimumPlaceTracks ? s : nil
    }
    static let minimumPlaceTracks = 8

    /// The year a track counts as: its own, its record's, or (for a signature tune with neither) nil.
    static func year(_ t: StationTrack, library: JazzLibrary) -> Int? {
        t.year ?? t.album.flatMap { library.album($0)?.year }
    }

    /// A station's tracks, in a fixed order (so a seed always gives the same sequence).
    static func pool(for station: Station, library: JazzLibrary, isHeard: (String) -> Bool) -> [StationTrack] {
        unsortedPool(for: station, library: library, isHeard: isHeard).sorted { $0.ref < $1.ref }
    }

    private static func unsortedPool(for station: Station, library: JazzLibrary, isHeard: (String) -> Bool) -> [StationTrack] {
        // Songbook versions ("artist|title|year") play on the Songbook's stations; the others use the guide's tracks.
        let all = library.tracks.values.filter { ($0.track.preview != nil || $0.track.url != nil) && $0.ref.split(separator: "|").count == 2 }
        switch station.kind {
        case .era(let e):
            return all.filter { $0.era == e || ($0.album.flatMap { library.album($0)?.era } == e) }
        case .decade(let d):
            return all.filter { year($0, library: library).map { $0 / 10 * 10 == d } ?? false }
        case .instrument(let f):
            return all.filter { t in
                if let a = library.artist(ofTrack: t), Passport.family(a.instrument) == f { return true }
                guard let album = t.album, let s = library.session(for: album) else { return false }
                return s.players(on: t.track.name).contains { $0.instruments.contains { Passport.family($0) == f } }
            }
        case .longWay:
            return all.filter { year($0, library: library) != nil }
        case .newToYou:
            return all.filter { t in t.album.map { !isHeard($0) } ?? true }
        case .tune(let id):
            guard let tune = library.tune(id) else { return [] }
            return tune.sortedVersions.compactMap { library.track(for: $0, of: tune) }
        case .songbook:
            return library.tunes.flatMap { t in t.versions.compactMap { library.track(for: $0, of: t) } }
        case .lineage(let id):
            return library.lineage(id)?.players.compactMap { $0.track.flatMap { library.tracks[$0] } } ?? []
        case .place(let id):
            let made = Set(library.albums(recordedAt: id).map(\.id))
            let people = Set(library.artists(at: id).map(\.id))
            return all.filter { t in
                if let a = t.album, made.contains(a) { return true }
                return library.artist(ofTrack: t).map { people.contains($0.id) } ?? false
            }
        case .label(let id):
            let records = Set(library.albums(onLabel: id).map(\.id))
            return all.filter { $0.album.map { records.contains($0) } ?? false }
        }
    }

    /// Orders a pool: a seeded shuffle with no artist twice in a row and no record twice within five tracks, opening
    /// with one of the era's essential tracks. The Long Way instead goes through time, two or three tracks per era.
    static func sequence(_ pool: [StationTrack], for station: Station, library: JazzLibrary, seed: UInt64,
                         count: Int = 100) -> [StationTrack] {
        var rng = SeededRandom(seed: seed)
        if station.kind == .longWay {
            var out: [StationTrack] = []
            for era in library.eras {
                let inEra = pool.filter { ($0.era ?? $0.album.flatMap { library.album($0)?.era }) == era.id }
                var picks = Array(inEra.shuffled(using: &rng).prefix(Int.random(in: 2...3, using: &rng)))
                picks.sort { (year($0, library: library) ?? 0) < (year($1, library: library) ?? 0) }
                out += picks
            }
            return spaced(out, library: library)
        }
        var bag = pool.shuffled(using: &rng)
        // Open with something unmistakable: an essential track of the station's era, or of the first track's.
        let essentials = Set(library.eras.flatMap(\.essentialTracks).map(\.id))
        if case .era(let e) = station.kind,
           let i = bag.firstIndex(where: { essentials.contains($0.ref) && $0.era == e }) {
            bag.swapAt(0, i)
        } else if let i = bag.firstIndex(where: { essentials.contains($0.ref) }) {
            bag.swapAt(0, i)
        }
        var out: [StationTrack] = []
        var pending = bag
        while out.count < count && !pool.isEmpty {
            if pending.isEmpty { pending = pool.shuffled(using: &rng) }
            let lastArtist = out.last.map(artistKey)
            let recentAlbums = Set(out.suffix(5).compactMap { $0.track.collectionId })
            let recentTracks = Set(out.suffix(max(1, pool.count / 2)).map(\.id))
            func fits(_ t: StationTrack, albums: Bool) -> Bool {
                artistKey(t) != lastArtist && !recentTracks.contains(t.id)
                    && (!albums || !(t.track.collectionId.map(recentAlbums.contains) ?? false))
            }
            // The bag first; then anything in the pool that fits; only then let a record come back early.
            if let i = pending.firstIndex(where: { fits($0, albums: true) }) {
                out.append(pending.remove(at: i))
            } else if let t = pool.shuffled(using: &rng).first(where: { fits($0, albums: true) }) {
                out.append(t)
                pending.removeAll { $0.id == t.id }
            } else if let t = pool.shuffled(using: &rng).first(where: { fits($0, albums: false) }) {
                out.append(t)
                pending.removeAll { $0.id == t.id }
            } else {
                break
            }
        }
        return out
    }

    /// The Long Way keeps its order, but moves a track along (within its era) when it would repeat the artist before it.
    private static func spaced(_ list: [StationTrack], library: JazzLibrary) -> [StationTrack] {
        var out = list
        let era = { (t: StationTrack) in t.era ?? t.album.flatMap { library.album($0)?.era } }
        for i in out.indices.dropFirst() where artistKey(out[i]) == artistKey(out[i - 1]) {
            if let j = out.indices.dropFirst(i + 1).first(where: {
                era(out[$0]) == era(out[i]) && artistKey(out[$0]) != artistKey(out[i - 1])
            }) {
                out.swapAt(i, j)
            }
        }
        return out
    }

    static func artistKey(_ t: StationTrack) -> String { t.artistName.lowercased() }

    /// Why a track is on: where it's from, then what the guide says about that record, year or artist.
    static func reason(for t: StationTrack, library: JazzLibrary) -> String {
        let y = year(t, library: library)
        // A Songbook version: what to listen for.
        if let (tune, v) = songbookVersion(t, library: library) {
            return "\(tune.title), \(v.artistName), \(String(v.year)). \(v.note)"
        }
        if let id = t.album, let album = library.album(id) {
            return "From \(album.title) (\(String(album.year))). \(firstSentence(album.why))"
        }
        var s = "\(t.artistName)"
        if let y { s += ", \(String(y))" }
        if let y, let m = library.milestones.first(where: { $0.year == y }) {
            return s + ". That year: \(m.title)."
        }
        if let a = library.artist(ofTrack: t), !a.blurb.isEmpty { return s + ". " + firstSentence(a.blurb) }
        if let e = t.era.flatMap({ library.era($0) }) { return s + ". \(e.name): \(e.tagline)." }
        return s + "."
    }

    /// The Songbook version a track is, from its "artist|title|year" ref.
    static func songbookVersion(_ t: StationTrack, library: JazzLibrary) -> (Tune, TuneVersion)? {
        let parts = t.ref.split(separator: "|")
        guard parts.count == 3 else { return nil }
        for tune in library.tunes {
            if let v = tune.versions.first(where: { $0.ref(in: tune) == t.ref }) { return (tune, v) }
        }
        return nil
    }

    static func firstSentence(_ text: String) -> String {
        guard let r = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) else { return text }
        return String(text[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
    }
}

/// SplitMix64: a small, seedable random number generator, so a station's order (and tests) can be repeated.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
