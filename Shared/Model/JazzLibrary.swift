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

    /// Symmetric connection graph.
    var edges: [(String, String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for a in artists {
            for b in a.connections where artistByID[b] != nil {
                let key = a.id < b ? "\(a.id)|\(b)" : "\(b)|\(a.id)"
                if seen.insert(key).inserted { out.append((a.id, b)) }
            }
        }
        return out
    }

    func neighbors(of id: String) -> Set<String> {
        var s = Set(artistByID[id]?.connections ?? [])
        for a in artists where a.connections.contains(id) { s.insert(a.id) }
        return s
    }

    struct SearchResults { var eras: [Era] = []; var artists: [Artist] = []; var albums: [Album] = []
        var isEmpty: Bool { eras.isEmpty && artists.isEmpty && albums.isEmpty } }

    func search(_ q: String) -> SearchResults {
        let q = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SearchResults() }
        func m(_ s: String) -> Bool { s.folding(options: .diacriticInsensitive, locale: nil).lowercased().contains(q) }
        return SearchResults(
            eras: eras.filter { m($0.name) || m($0.tagline) },
            artists: artists.filter { m($0.name) || m($0.instrument) },
            albums: albums.filter { m($0.title) || m($0.artistName) || m($0.label) || String($0.year) == q }
        )
    }
}
