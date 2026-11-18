import Foundation

// Lineages: who learned from whom on each instrument (lineages.json). The Glossary: the words jazz uses, each with a
// recording to hear it in (glossary.json).

struct LineagePlayer: Codable, Hashable {
    let artist: String
    /// What they brought, in one sentence.
    let idea: String
    /// A track that shows it ("artist|title" in tracks.json).
    var track: String? = nil
}

struct LineageLink: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case influence, teacher, bandmate, reaction }
    let from: String
    let to: String
    let kind: Kind
    /// Why the line is drawn: what carried over, and who said so.
    let note: String
    var id: String { "\(from)>\(to)" }

    var kindText: String {
        switch kind {
        case .influence: return "Influence"
        case .teacher: return "Teacher"
        case .bandmate: return "Learned on the bandstand"
        case .reaction: return "Reaction"
        }
    }
}

struct Lineage: Codable, Identifiable, Hashable {
    let id: String
    let family: String
    let title: String
    let intro: String
    let players: [LineagePlayer]
    let links: [LineageLink]

    func player(_ artistID: String) -> LineagePlayer? { players.first { $0.artist == artistID } }
}

struct LineagesData: Codable { let lineages: [Lineage] }

struct TermExample: Codable, Hashable {
    let track: String
    let note: String
}

struct GlossaryTerm: Codable, Identifiable, Hashable {
    let id: String
    let term: String
    var also: [String] = []
    let category: String
    /// A common word ("swing", "head") that's never linked automatically in prose.
    var explicitOnly: Bool? = nil
    let short: String
    let long: String
    let examples: [TermExample]
    var related: [String] = []

    var linksAutomatically: Bool { explicitOnly != true }
}

struct HowToListenStep: Codable, Hashable {
    let title: String
    let term: String
    let text: String
}

struct GlossaryData: Codable {
    let terms: [GlossaryTerm]
    var howToListen: [HowToListenStep] = []
    var howToListenTrack: String? = nil
}

extension JazzLibrary {
    func lineage(_ id: String) -> Lineage? { lineages.first { $0.id == id } }
    func lineages(including artistID: String) -> [Lineage] { lineages.filter { $0.player(artistID) != nil } }
    /// Who an artist came from, across every lineage.
    func roots(of artistID: String) -> [LineageLink] { lineages.flatMap(\.links).filter { $0.to == artistID } }
    /// Who came from them.
    func heirs(of artistID: String) -> [LineageLink] { lineages.flatMap(\.links).filter { $0.from == artistID } }

    func term(_ id: String) -> GlossaryTerm? { glossary.terms.first { $0.id == id } }
    var terms: [GlossaryTerm] { glossary.terms.sorted { $0.term.lowercased() < $1.term.lowercased() } }

    /// The year a player came of age, for placing them in time: born + 20, or their era's start.
    func comingOfAge(_ artistID: String) -> Int {
        guard let a = artist(artistID) else { return 1900 }
        if let b = a.born { return b + 20 }
        return era(a.primaryEra)?.start ?? 1900
    }
}

/// Places a lineage's faces: left to right by when each player came of age, in lanes chosen so faces don't overlap,
/// each player as close as possible to the lane of the player they came from.
struct LineageLayout {
    struct Node: Hashable { let artist: String; let x: Double; let lane: Int }
    let nodes: [Node]
    let lanes: Int
    let minYear: Int
    let maxYear: Int

    /// `spacing` is the least distance, in years, between two faces in one lane.
    init(lineage: Lineage, library: JazzLibrary, spacing: Int = 12) {
        let players = lineage.players.map(\.artist).sorted {
            let a = library.comingOfAge($0), b = library.comingOfAge($1)
            return a != b ? a < b : $0 < $1
        }
        var laneEnds: [Int] = []          // last year used in each lane
        var laneOf: [String: Int] = [:]
        var out: [Node] = []
        for id in players {
            let year = library.comingOfAge(id)
            // Prefer the lane of a player this one came from.
            let parentLane = lineage.links.first { $0.to == id }.flatMap { laneOf[$0.from] } ?? 0
            let free = laneEnds.indices.filter { laneEnds[$0] + spacing <= year }
            let lane = free.min { abs($0 - parentLane) < abs($1 - parentLane) } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(year) } else { laneEnds[lane] = year }
            laneOf[id] = lane
            out.append(Node(artist: id, x: Double(year), lane: lane))
        }
        nodes = out
        lanes = max(1, laneEnds.count)
        minYear = out.map { Int($0.x) }.min() ?? 1900
        maxYear = out.map { Int($0.x) }.max() ?? 2000
    }

    func node(_ artistID: String) -> Node? { nodes.first { $0.artist == artistID } }
}
