import SwiftUI

/// One stop on a path: a record, a track, a tune, a term, an era, an artist or a place, with what to listen for.
struct PathStop: Codable, Hashable {
    enum Kind: String, Codable { case album, track, tune, term, era, artist, place }
    let kind: Kind
    let ref: String
    /// For an album: the track to start with ("artist|title").
    var track: String? = nil
    var note: String? = nil

    /// Stable across edits to the path: "album:kind-of-blue".
    var key: String { "\(kind.rawValue):\(ref)" }
}

/// A journey with a point of view (paths.json). Named so it doesn't collide with SwiftUI's Path.
struct JourneyPath: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tint: String
    let intro: String
    var stops: [PathStop]
    let outro: String
    var next: [String] = []

    var color: Color { Color(hex: tint) }

    private enum Keys: String, CodingKey { case id, title, subtitle, tint, intro, stops, outro, next }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        tint = try c.decode(String.self, forKey: .tint)
        intro = try c.decode(String.self, forKey: .intro)
        outro = try c.decode(String.self, forKey: .outro)
        next = try c.decodeIfPresent([String].self, forKey: .next) ?? []
        // "starters" means Start Here: the Crate's starter picks, filled in by the library.
        stops = (try? c.decode([PathStop].self, forKey: .stops)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(subtitle, forKey: .subtitle)
        try c.encode(tint, forKey: .tint); try c.encode(intro, forKey: .intro); try c.encode(stops, forKey: .stops)
        try c.encode(outro, forKey: .outro); try c.encode(next, forKey: .next)
    }

    init(id: String, title: String, subtitle: String, tint: String, intro: String, stops: [PathStop], outro: String, next: [String] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.tint = tint; self.intro = intro
        self.stops = stops; self.outro = outro; self.next = next
    }
}

struct PathsData: Codable { let paths: [JourneyPath] }

extension JazzLibrary {
    func journey(_ id: String) -> JourneyPath? { paths.first { $0.id == id } }

    /// Start Here's stops: the starter picks in order, each starting with its first highlight.
    static func starterStops(_ albums: [Album]) -> [PathStop] {
        albums.filter(\.starter).map { a in
            PathStop(kind: .album, ref: a.id, track: a.highlights.first.map { "\(a.artistName)|\($0)" }, note: nil)
        }
    }

    /// What a stop is called, and a line under it.
    func title(of stop: PathStop) -> (title: String, subtitle: String) {
        switch stop.kind {
        case .album: return album(stop.ref).map { ($0.title, "\($0.artistName) · \(String($0.year))") } ?? (stop.ref, "")
        case .track:
            let t = tracks[stop.ref]
            return (t?.title ?? stop.ref, [t?.artistName, t.flatMap { Programmer.year($0, library: self) }.map { String($0) }].compactMap { $0 }.joined(separator: " · "))
        case .tune: return tune(stop.ref).map { ($0.title, "The Songbook · \($0.versions.count) versions") } ?? (stop.ref, "")
        case .term: return term(stop.ref).map { ($0.term, "The Glossary") } ?? (stop.ref, "")
        case .era: return era(stop.ref).map { ($0.name, $0.years) } ?? (stop.ref, "")
        case .artist: return artist(stop.ref).map { ($0.name, "\($0.instrument) · \($0.lifespan)") } ?? (stop.ref, "")
        case .place: return place(stop.ref).map { ($0.name, "\($0.kindLabel) · \($0.years)") } ?? (stop.ref, "")
        }
    }

    /// The track a stop plays, if any.
    func playable(_ stop: PathStop) -> StationTrack? {
        switch stop.kind {
        case .track: return tracks[stop.ref]
        case .album: return stop.track.flatMap { tracks[$0] }
        default: return nil
        }
    }
}

extension Passport {
    /// Whether a stop is done: its record heard, its track played through, or ticked (by hand, or by opening it from
    /// the path).
    func isDone(_ stop: PathStop, on path: JourneyPath, library: JazzLibrary) -> Bool {
        if data.paths?[path.id]?[stop.key] != nil { return true }
        switch stop.kind {
        case .album: return isHeard(stop.ref)
        case .track: return library.tracks[stop.ref].map { data.songsHeard?[String($0.id)] != nil } ?? false
        default: return false
        }
    }

    func progress(on path: JourneyPath, library: JazzLibrary) -> (done: Int, total: Int, next: Int?) {
        let done = path.stops.map { isDone($0, on: path, library: library) }
        return (done.filter { $0 }.count, path.stops.count, done.firstIndex(of: false))
    }

    func isStarted(_ path: JourneyPath, library: JazzLibrary) -> Bool { progress(on: path, library: library).done > 0 }
    func isFinished(_ path: JourneyPath, library: JazzLibrary) -> Bool {
        let p = progress(on: path, library: library); return p.total > 0 && p.done == p.total
    }

    /// The path in progress that was touched most recently.
    func currentPath(library: JazzLibrary) -> JourneyPath? {
        library.paths.filter { isStarted($0, library: library) && !isFinished($0, library: library) }
            .max { lastTouched($0) < lastTouched($1) }
    }

    private func lastTouched(_ path: JourneyPath) -> Date {
        (data.paths?[path.id]?.values.max()) ?? .distantPast
    }
}
