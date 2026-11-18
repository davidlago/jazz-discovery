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

    init(data: JazzData, sessions: [String: Session] = [:]) {
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

    static func load(from bundle: Bundle = .main) -> JazzLibrary {
        guard let url = bundle.url(forResource: "jazz", withExtension: "json") else {
            fatalError("jazz.json missing from bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return JazzLibrary(data: try JSONDecoder().decode(JazzData.self, from: data),
                               sessions: optional([String: Session].self, "sessions", in: bundle) ?? [:])
        } catch {
            fatalError("Could not decode jazz.json: \(error)")
        }
    }

    /// A data file that may not be there (a section still being written). Missing or unreadable means empty, so the
    /// app still opens; scripts/validate-data.py and the unit tests catch a file that doesn't decode.
    static func optional<T: Decodable>(_ type: T.Type, _ name: String, in bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func era(_ id: String) -> Era? { eraByID[id] }
    func artist(_ id: String) -> Artist? { artistByID[id] }
    func album(_ id: String) -> Album? { albumByID[id] }

    func artists(_ ids: [String]) -> [Artist] { ids.compactMap { artistByID[$0] } }
    func albums(_ ids: [String]) -> [Album] { ids.compactMap { albumByID[$0] } }

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
        var isEmpty: Bool { eras.isEmpty && artists.isEmpty && albums.isEmpty && players.isEmpty } }

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
        return SearchResults(
            eras: eras.filter { m($0.name) || m($0.tagline) },
            artists: artists.filter { m($0.name) || m($0.instrument) },
            albums: albums.filter { m($0.title) || m($0.artistName) || m($0.label) || String($0.year) == q },
            players: Array(players.prefix(20))
        )
    }
}
