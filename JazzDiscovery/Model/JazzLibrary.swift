import SwiftUI
import Observation

@Observable
final class JazzLibrary {
    let eras: [Era]
    let artists: [Artist]
    let albums: [Album]
    let milestones: [Milestone]

    private let eraByID: [String: Era]
    private let artistByID: [String: Artist]
    private let albumByID: [String: Album]

    init(data: JazzData) {
        eras = data.eras.sorted { $0.start < $1.start }
        artists = data.artists
        albums = data.albums.sorted { $0.year < $1.year }
        milestones = data.milestones.sorted { $0.year < $1.year }
        eraByID = Dictionary(data.eras.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        artistByID = Dictionary(data.artists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        albumByID = Dictionary(data.albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func load() -> JazzLibrary {
        guard let url = Bundle.main.url(forResource: "jazz", withExtension: "json") else {
            fatalError("jazz.json missing from bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return JazzLibrary(data: try JSONDecoder().decode(JazzData.self, from: data))
        } catch {
            fatalError("Could not decode jazz.json: \(error)")
        }
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

enum Route: Hashable {
    case era(String)
    case artist(String)
    case album(String)
    case decade(Int)
}

enum AppSection: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case eras = "Eras & Styles"
    case decades = "Decades"
    case artists = "Artists"
    case albums = "The Crate"
    case connections = "Connections"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .timeline: return "timeline.selection"
        case .eras: return "square.stack.3d.up.fill"
        case .decades: return "calendar"
        case .artists: return "person.2.fill"
        case .albums: return "square.grid.3x3.fill"
        case .connections: return "point.3.connected.trianglepath.dotted"
        }
    }
}

@Observable
final class Router {
    var section: AppSection = .timeline
    var path: [Route] = []

    func go(_ route: Route) { path.append(route) }
    func back() { if !path.isEmpty { path.removeLast() } }
    func show(_ section: AppSection) { self.section = section; path = [] }
}
