import SwiftUI
import Observation

@Observable
final class JazzLibrary {
    let eras: [Era]
    let artists: [Artist]
    let albums: [Album]
    let milestones: [Milestone]
    /// Reviewed sessions only, by album ID (sessions.json; drafts are left out).
    let sessions: [String: Session]

    private let eraByID: [String: Era]
    private let artistByID: [String: Artist]
    private let albumByID: [String: Album]
    /// Artist ID → IDs of the albums they're credited on (as a player), led or not.
    private let creditedAlbums: [String: Set<String>]
    /// Every connection between two artists in the guide, strongest first.
    let ties: [Tie]
    private let tieByPair: [String: Tie]
    private let tiesByArtist: [String: [Tie]]
    /// Every named track resolved to Apple Music ahead of time (tracks.json), by "artist|title".
    let tracks: [String: StationTrack]
    /// Each Crate album's Apple Music tracks (tracklists.json), by album ID.
    let tracklists: [String: [CatalogTrack]]
    /// The Songbook's tunes, A–Z (songbook.json).
    let tunes: [Tune]
    /// Cities, rooms, studios and festivals (places.json), and labels with pages (labels.json).
    let places: [Place]
    let labels: [LabelInfo]
    /// Instrument family trees (lineages.json), the glossary (glossary.json), and the linker that finds its terms.
    let lineages: [Lineage]
    let glossary: GlossaryData
    /// Journeys with a point of view (paths.json); Start Here's stops come from the starter picks.
    let paths: [JourneyPath]
    /// Births, deaths and sessions by day of the year (almanac.json).
    let almanac: AlmanacData
    /// Listening guides (guides.json). A var so the Mac's guide editor can try new times on the running app.
    var guides: [Guide]
    let termLinker: TermLinker
    private let tuneByID: [String: Tune]
    /// Title key → tune, from titles and aliases.
    private let tuneByKey: [String: Tune]

    init(data: JazzData, sessions: [String: Session] = [:], tracks: [String: StationTrack] = [:],
         tracklists: [String: [CatalogTrack]] = [:], tunes: [Tune] = [], places: [Place] = [], labels: [LabelInfo] = [],
         lineages: [Lineage] = [], glossary: GlossaryData = GlossaryData(terms: []), paths: [JourneyPath] = [],
         almanac: AlmanacData = AlmanacData(), guides: [Guide] = []) {
        self.almanac = almanac
        self.guides = guides
        self.paths = paths.map { p in
            guard p.id == "start-here", p.stops.isEmpty else { return p }
            var filled = p
            filled.stops = JazzLibrary.starterStops(data.albums.sorted { $0.year < $1.year })
            return filled
        }
        self.places = places
        self.labels = labels
        self.lineages = lineages
        self.glossary = glossary
        termLinker = TermLinker(terms: glossary.terms,
                                protectedNames: data.artists.map(\.name) + data.albums.map(\.title) + tunes.map(\.title)
                                    + data.eras.flatMap { [$0.name, $0.stamp ?? ""] })
        self.tracks = StationTrack.load(tracks)
        self.tracklists = tracklists
        self.tunes = tunes.sorted { Tune.key($0.title) < Tune.key($1.title) }
        tuneByID = Dictionary(tunes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var byKey: [String: Tune] = [:]
        for t in tunes { for k in t.keys { byKey[k] = t } }
        tuneByKey = byKey
        eras = data.eras.sorted { $0.start < $1.start }
        artists = data.artists
        albums = data.albums.sorted { $0.year < $1.year }
        milestones = data.milestones.sorted { $0.year < $1.year }
        eraByID = Dictionary(data.eras.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        artistByID = Dictionary(data.artists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let albumByID = Dictionary(data.albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.albumByID = albumByID
        let reviewed = sessions.filter { $0.value.reviewed && albumByID[$0.key] != nil }
        self.sessions = reviewed
        var credited: [String: Set<String>] = [:]
        for (albumID, session) in reviewed {
            for case let id? in session.personnel.map(\.artist) { credited[id, default: []].insert(albumID) }
        }
        creditedAlbums = credited

        // Ties: records both are on (as leader or player), bonds, and hand-picked connections.
        let known = Set(data.artists.map(\.id))
        func pairKey(_ x: String, _ y: String) -> String { x < y ? "\(x)|\(y)" : "\(y)|\(x)" }
        var shared: [String: [Album]] = [:]
        for (albumID, session) in reviewed {
            guard let album = albumByID[albumID] else { continue }
            let people = Set(session.personnel.compactMap(\.artist) + [album.artist]).filter(known.contains).sorted()
            for (i, x) in people.enumerated() {
                for y in people[(i + 1)...] { shared[pairKey(x, y), default: []].append(album) }
            }
        }
        var bonds: [String: Bond] = [:]
        for bond in data.bonds ?? [] where known.contains(bond.a) && known.contains(bond.b) && bond.a != bond.b {
            bonds[pairKey(bond.a, bond.b)] = bond
        }
        var curated = Set<String>()
        for artist in data.artists {
            for other in artist.connections where known.contains(other) && other != artist.id {
                curated.insert(pairKey(artist.id, other))
            }
        }
        var byPair: [String: Tie] = [:]
        for key in Set(shared.keys).union(bonds.keys).union(curated) {
            let ids = key.split(separator: "|").map(String.init)
            byPair[key] = Tie(a: ids[0], b: ids[1],
                              albums: (shared[key] ?? []).sorted { ($0.year, $0.title) < ($1.year, $1.title) },
                              bond: bonds[key], curated: curated.contains(key))
        }
        let all = byPair.values.sorted { ($0.weight, $1.id) > ($1.weight, $0.id) }
        ties = all
        tieByPair = byPair
        var byArtist: [String: [Tie]] = [:]
        for tie in all { byArtist[tie.a, default: []].append(tie); byArtist[tie.b, default: []].append(tie) }
        tiesByArtist = byArtist
    }

    static func load(from bundle: Bundle) -> JazzLibrary { load(from: ContentFiles(bundle: bundle)) }

    /// The library from this launch's data files (Content.swift): downloaded ones when there are any, else the bundle's.
    static func load(from files: ContentFiles = .active) -> JazzLibrary {
        do {
            return try make(files, strict: false)
        } catch where files.folder != nil {
            // Downloaded files are checked before they're used, so this is a damaged copy: the bundle's are complete.
            JazzContent.log.error("Downloaded content didn't load (\(String(describing: error), privacy: .public)); using the built-in content")
            return load(from: ContentFiles(bundle: files.bundle))
        } catch {
            fatalError("Could not load jazz.json: \(error)")
        }
    }

    /// Reads every data file as the app does, and throws at the first one that doesn't decode (a missing optional file
    /// is fine). Content.swift runs it on downloaded files before using them.
    static func validate(_ files: ContentFiles) throws {
        _ = try make(files, strict: true)
        // Read on their own by the iTunes lookups and the passport.
        _ = try decode([String: CatalogAlbum].self, "catalog", in: files, strict: true)
        _ = try decode([String: CatalogTrack].self, "tracks", in: files, strict: true)
        _ = try decode([String: [CatalogTrack]].self, "tracklists", in: files, strict: true)
    }

    private static func make(_ files: ContentFiles, strict: Bool) throws -> JazzLibrary {
        guard let data = files.data("jazz") else { throw ContentError.missing("jazz.json") }
        let jazz: JazzData
        do { jazz = try JSONDecoder().decode(JazzData.self, from: data) } catch { throw ContentError.unreadable("jazz.json", error) }
        func opt<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? { try decode(type, name, in: files, strict: strict) }
        return JazzLibrary(data: jazz,
                           sessions: try opt([String: Session].self, "sessions") ?? [:],
                           tracks: try opt([String: StationTrack].self, "tracks") ?? [:],
                           tracklists: try opt([String: [CatalogTrack]].self, "tracklists") ?? [:],
                           tunes: try opt(SongbookData.self, "songbook")?.tunes ?? [],
                           places: try opt(PlacesData.self, "places")?.places ?? [],
                           labels: try opt(LabelsData.self, "labels")?.labels ?? [],
                           lineages: try opt(LineagesData.self, "lineages")?.lineages ?? [],
                           glossary: try opt(GlossaryData.self, "glossary") ?? GlossaryData(terms: []),
                           paths: try opt(PathsData.self, "paths")?.paths ?? [],
                           almanac: try opt(AlmanacData.self, "almanac") ?? AlmanacData(),
                           guides: try opt(GuidesData.self, "guides")?.guides ?? [])
    }

    /// A data file that may not be there (a section still being written). Missing means nil; unreadable means nil too,
    /// so the app still opens, unless `strict` (checking downloaded files), where it throws.
    private static func decode<T: Decodable>(_ type: T.Type, _ name: String, in files: ContentFiles, strict: Bool) throws -> T? {
        guard let data = files.data(name) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if strict { throw ContentError.unreadable("\(name).json", error) }
            return nil
        }
    }

    static func optional<T: Decodable>(_ type: T.Type, _ name: String, in files: ContentFiles = .active) -> T? {
        try? decode(type, name, in: files, strict: false)
    }

    func era(_ id: String) -> Era? { eraByID[id] }
    func artist(_ id: String) -> Artist? { artistByID[id] }
    func album(_ id: String) -> Album? { albumByID[id] }

    func artists(_ ids: [String]) -> [Artist] { ids.compactMap { artistByID[$0] } }
    func albums(_ ids: [String]) -> [Album] { ids.compactMap { albumByID[$0] } }

    /// The artist a resolved track is by: the one named in its ref, or its record's leader.
    func artist(ofTrack t: StationTrack) -> Artist? {
        let name = t.artistName
        return artists.first { $0.name == name } ?? t.album.flatMap { album($0) }.flatMap { artist($0.artist) }
            ?? artist(named: name)
    }

    /// The tune with this title key, if any.
    func tunesByKey(_ key: String) -> Tune? { tuneByKey[key] }

    /// A named track, resolved ahead of time.
    func track(_ ref: TrackRef) -> StationTrack? { tracks[ref.id] }
    func track(_ title: String, by artist: String) -> StationTrack? { tracks["\(artist)|\(title)"] }

    func artist(named name: String) -> Artist? {
        let n = name.lowercased()
        return artists.first { n.hasPrefix($0.name.lowercased()) }
    }

    func color(forEra id: String) -> Color { eraByID[id]?.tint ?? .gray }

    func albums(inEra id: String) -> [Album] { albums.filter { $0.era == id } }
    func artists(inEra id: String) -> [Artist] { artists.filter { $0.eras.contains(id) } }
    func albums(inDecade d: Int) -> [Album] { albums.filter { $0.decade == d } }
    func eras(inDecade d: Int) -> [Era] { eras.filter { $0.overlaps(decade: d) } }
    func milestones(inDecade d: Int) -> [Milestone] { milestones.filter { $0.year / 10 * 10 == d } }
    /// Who was playing in a decade: of age then, and in one of the styles of the time.
    func players(inDecade d: Int) -> [Artist] {
        let eras = Set(eras(inDecade: d).map(\.id))
        return artists.filter { a in a.active(in: d) && a.eras.contains { eras.contains($0) } }
    }
    /// What a decade's tile counts: its records ("11 records"), or, for a decade before the first record here, who
    /// was playing ("5 players"), so it doesn't read "0 records".
    func decadeCount(_ d: Int) -> String {
        let records = albums(inDecade: d).count
        if records > 0 { return "\(records) record\(records == 1 ? "" : "s")" }
        let players = players(inDecade: d).count
        return "\(players) player\(players == 1 ? "" : "s")"
    }
    func albums(by artistID: String) -> [Album] {
        let listed = artistByID[artistID]?.albums ?? []
        var result = albums(listed)
        for a in albums where a.artist == artistID && !listed.contains(a.id) { result.append(a) }
        return result.sorted { $0.year < $1.year }
    }

    // MARK: Sessions

    /// Who played on an album, when and where: nil until its session has been reviewed.
    func session(for albumID: String) -> Session? { sessions[albumID] }

    /// Albums the artist plays on but doesn't lead, in year order.
    func appearances(of artistID: String) -> [Album] {
        (creditedAlbums[artistID] ?? []).compactMap { albumByID[$0] }
            .filter { $0.artist != artistID }
            .sorted { ($0.year, $0.title) < ($1.year, $1.title) }
    }

    /// Albums both artists are on (leading or playing), in year order.
    func sharedAlbums(_ a: String, _ b: String) -> [Album] {
        func on(_ id: String) -> Set<String> {
            (creditedAlbums[id] ?? []).union(albums.filter { $0.artist == id && sessions[$0.id] != nil }.map(\.id))
        }
        return on(a).intersection(on(b)).compactMap { albumByID[$0] }.sorted { ($0.year, $0.title) < ($1.year, $1.title) }
    }

    /// The artist's credit on an album (instruments, which tracks), when its session is reviewed.
    func credit(of artistID: String, on albumID: String) -> Credit? {
        sessions[albumID]?.personnel.first { $0.artist == artistID }
    }

    /// Whether the artist leads a record in the Crate.
    func leads(_ artistID: String) -> Bool { !albums(by: artistID).isEmpty }

    /// A sideman: no record of their own in the Crate, known from the ones they play on. (Figures with neither, such
    /// as Scott Joplin or Art Tatum, count as leaders.)
    func isSideman(_ artistID: String) -> Bool { !leads(artistID) && !appearances(of: artistID).isEmpty }

    /// Artists with at least one tie to another artist in the guide, for the Connections map.
    var connectedArtists: [Artist] { artists.filter { tiesByArtist[$0.id] != nil } }

    // MARK: Ties and paths

    /// Why two artists are connected, if they are.
    func tie(_ x: String, _ y: String) -> Tie? { tieByPair[x < y ? "\(x)|\(y)" : "\(y)|\(x)"] }

    /// An artist's ties, strongest first.
    func ties(of id: String) -> [Tie] { tiesByArtist[id] ?? [] }

    /// The shortest chain of ties from one artist to another: fewest links first, then links through more records
    /// together rather than bonds. Nil when they aren't connected (or are the same artist).
    func path(from start: String, to goal: String) -> [PathStep]? {
        guard start != goal, tiesByArtist[start] != nil, tiesByArtist[goal] != nil else { return nil }
        func cost(_ t: Tie) -> Double { t.albums.isEmpty ? 1.6 : 1 + 0.5 / Double(1 + t.albums.count) }
        var best: [String: Double] = [start: 0]
        var via: [String: (from: String, tie: Tie)] = [:]
        var open: Set<String> = [start]
        var done = Set<String>()
        while let current = open.min(by: { (best[$0] ?? .infinity, $0) < (best[$1] ?? .infinity, $1) }) {
            open.remove(current)
            if current == goal { break }
            done.insert(current)
            for tie in tiesByArtist[current] ?? [] {
                let next = tie.other(than: current)
                guard !done.contains(next) else { continue }
                let d = (best[current] ?? .infinity) + cost(tie)
                if d < best[next] ?? .infinity {
                    best[next] = d
                    via[next] = (current, tie)
                    open.insert(next)
                }
            }
        }
        guard via[goal] != nil else { return nil }
        var steps: [PathStep] = []
        var at = goal
        while let step = via[at] {
            steps.append(PathStep(from: step.from, to: at, tie: step.tie))
            at = step.from
        }
        return steps.reversed()
    }

    /// The instruments an artist is credited with across the reviewed albums, most albums first.
    func instruments(of artistID: String) -> [String] {
        var count: [String: Int] = [:]
        for albumID in creditedAlbums[artistID] ?? [] {
            for credit in sessions[albumID]?.personnel ?? [] where credit.artist == artistID {
                for i in credit.instruments { count[i, default: 0] += 1 }
            }
        }
        return count.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    var decades: [Int] { Array(stride(from: 1890, through: 2020, by: 10)) }
    var instruments: [String] {
        Array(Set(artists.map(\.instrument))).sorted()
    }
    var starterPath: [Album] { albums.filter(\.starter) }

    /// The connection graph's edges, one per tie.
    var edges: [(String, String)] { ties.map { ($0.a, $0.b) } }

    /// Everyone tied to an artist.
    func neighbors(of id: String) -> Set<String> { Set(ties(of: id).map { $0.other(than: id) }) }

    /// Someone credited on the records who has no page of their own.
    struct Player: Identifiable, Hashable {
        let name: String
        let instruments: [String]
        let albums: [Album]
        var id: String { name }
    }

    struct SearchResults { var eras: [Era] = []; var artists: [Artist] = []; var albums: [Album] = []
        var players: [Player] = []
        var tunes: [Tune] = []
        var places: [Place] = []
        var labels: [LabelInfo] = []
        var terms: [GlossaryTerm] = []
        var paths: [JourneyPath] = []
        var guides: [Guide] = []
        var isEmpty: Bool {
            eras.isEmpty && artists.isEmpty && albums.isEmpty && players.isEmpty && tunes.isEmpty && places.isEmpty
                && labels.isEmpty && terms.isEmpty && paths.isEmpty && guides.isEmpty
        }
    }

    func search(_ q: String) -> SearchResults {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SearchResults() }
        func m(_ s: String) -> Bool { s.folding(options: .diacriticInsensitive, locale: nil).lowercased().contains(q) }
        // Players without a page, by name: the records they're on.
        var byName: [String: (instruments: [String], albums: [Album])] = [:]
        for (albumID, session) in sessions {
            guard let album = albumByID[albumID] else { continue }
            for credit in session.personnel where credit.artist == nil && m(credit.name) {
                var entry = byName[credit.name] ?? ([], [])
                for i in credit.instruments where !entry.instruments.contains(i) { entry.instruments.append(i) }
                if !entry.albums.contains(album) { entry.albums.append(album) }
                byName[credit.name] = entry
            }
        }
        let players = byName.map { Player(name: $0.key, instruments: $0.value.instruments,
                                          albums: $0.value.albums.sorted { $0.year < $1.year }) }
            .sorted { ($0.albums.count, $1.name) > ($1.albums.count, $0.name) }
        let rank = SearchRank(q)
        return SearchResults(
            eras: rank.sorted(eras) { ([$0.name], [$0.tagline]) },
            artists: rank.sorted(artists) { ([$0.name], [$0.instrument]) },
            // A starter record goes before others that match as well, then the oldest; the year matches only exactly.
            albums: rank.sorted(albums.sorted { $0.year < $1.year }, first: \.starter) { a in
                ([a.title], [a.artistName, a.label] + (String(a.year) == q ? [q] : []))
            },
            players: Array(players.prefix(20)),
            tunes: rank.sorted(tunes) { t in ([t.title] + (t.aliases ?? []), t.composers.map(composerName)) },
            places: rank.sorted(places) { ([$0.name], $0.city.map { [$0] } ?? []) },
            labels: rank.sorted(labels) { ([$0.name], $0.matches) },
            terms: rank.sorted(glossary.terms) { ([$0.term], $0.also) },
            paths: rank.sorted(paths) { ([$0.title], [$0.subtitle]) },
            guides: rank.sorted(guides) { g in tracks[g.track].map { ([$0.title], [$0.artistName]) } ?? ([], []) }
        )
    }
}

/// How well a search matches, best first: the query is the whole of an item's name, then a whole word in it ("Kind
/// of Blue" for "blue"), then the start of a word ("Bluebird"), then anywhere in it; and a match in the name before one
/// in a secondary field (an album's artist or label, an era's tagline). Items that match equally keep the library's
/// order (eras, artists and records by date).
struct SearchRank {
    let query: String

    init(_ query: String) { self.query = Self.fold(query) }

    static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: nil).lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// 0 (the whole text) to 3 (somewhere inside it), or nil when the text doesn't contain the query.
    func score(_ text: String) -> Int? {
        let t = Self.fold(text)
        guard !query.isEmpty, t.contains(query) else { return nil }
        if t == query { return 0 }
        func isWordStart(_ i: String.Index) -> Bool { i == t.startIndex || !t[t.index(before: i)].isLetter && !t[t.index(before: i)].isNumber }
        func isWordEnd(_ i: String.Index) -> Bool { i == t.endIndex || !t[i].isLetter && !t[i].isNumber }
        var best = 3
        var from = t.startIndex
        while let r = t.range(of: query, range: from..<t.endIndex) {
            if isWordStart(r.lowerBound) { best = min(best, isWordEnd(r.upperBound) ? 1 : 2) }
            if best == 1 { break }
            from = t.index(after: r.lowerBound)
        }
        return best
    }

    /// The item's rank: its best match in its main fields, or 4 more than its best in the others; nil if none match.
    func rank(main: [String], other: [String]) -> Int? {
        if let s = main.compactMap(score).min() { return s }
        return other.compactMap(score).min().map { $0 + 4 }
    }

    /// The items that match, best first; `first` breaks ties (true before false), then the items' own order.
    func sorted<T>(_ items: [T], first: ((T) -> Bool)? = nil, fields: (T) -> (main: [String], other: [String])) -> [T] {
        items.enumerated()
            .compactMap { i, item -> (rank: Int, lead: Int, index: Int, item: T)? in
                let f = fields(item)
                guard let r = rank(main: f.main, other: f.other) else { return nil }
                return (r, first.map { $0(item) ? 0 : 1 } ?? 0, i, item)
            }
            .sorted { ($0.rank, $0.lead, $0.index) < ($1.rank, $1.lead, $1.index) }
            .map(\.item)
    }
}
