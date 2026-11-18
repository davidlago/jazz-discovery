import Foundation
import Testing

@Suite("Ties and paths")
struct TieTests {
    /// Kind of Blue (Miles, Coltrane) and Giant Steps (Coltrane) reviewed; Miles–Parker hand-picked;
    /// Parker–Gilberto a bond; Bitches Brew a draft.
    static let library: JazzLibrary = {
        let base = SessionTests.library
        let data = JazzData(eras: base.eras, artists: base.artists, albums: base.albums, milestones: [],
                            bonds: [Bond(a: "joao-gilberto", b: "charlie-parker", kind: "influence", note: "A test bond."),
                                    Bond(a: "nobody", b: "miles-davis", kind: "band", note: "Unknown artist: ignored.")])
        return JazzLibrary(data: data, sessions: base.sessions)
    }()

    @Test func tiesCombineRecordsBondsAndConnections() {
        let mt = Self.library.tie("miles-davis", "john-coltrane")!
        #expect(mt.albums.map(\.id) == ["kind-of-blue"])
        #expect(mt.curated && mt.bond == nil && mt.weight == 1)
        #expect(Self.library.tie("john-coltrane", "miles-davis") == mt)   // either order

        let mp = Self.library.tie("miles-davis", "charlie-parker")!
        #expect(mp.albums.isEmpty && mp.curated && mp.weight == 0 && mp.prominent)

        let pj = Self.library.tie("charlie-parker", "joao-gilberto")!
        #expect(pj.bond?.kind == "influence" && !pj.curated && pj.weight == 1)

        #expect(Self.library.tie("miles-davis", "nobody") == nil)
        #expect(Self.library.tie("john-coltrane", "joao-gilberto") == nil)
    }

    @Test("A draft session ties nobody")
    func draftsDontCount() {
        #expect(Self.library.tie("miles-davis", "john-coltrane")?.albums.contains { $0.id == "bitches-brew" } == false)
    }

    @Test func tiesOfAnArtist() {
        #expect(Set(Self.library.ties(of: "charlie-parker").map { $0.other(than: "charlie-parker") }) == ["miles-davis", "joao-gilberto"])
        #expect(Set(Self.library.connectedArtists.map(\.id)) == ["miles-davis", "john-coltrane", "charlie-parker", "joao-gilberto"])
    }

    @Test func paths() {
        let p = Self.library.path(from: "joao-gilberto", to: "john-coltrane")!
        #expect(p.map(\.from) == ["joao-gilberto", "charlie-parker", "miles-davis"])
        #expect(p.map(\.to) == ["charlie-parker", "miles-davis", "john-coltrane"])
        #expect(p.last?.tie.albums.map(\.id) == ["kind-of-blue"])
        // The reverse is the same chain backwards.
        let back = Self.library.path(from: "john-coltrane", to: "joao-gilberto")!
        #expect(back.map(\.to) == ["miles-davis", "charlie-parker", "joao-gilberto"])
        #expect(Self.library.path(from: "miles-davis", to: "miles-davis") == nil)
        #expect(Self.library.path(from: "miles-davis", to: "nobody") == nil)
    }

    @Test("Of two equally short chains, the one through records wins")
    func pathsPreferRecords() {
        // a–b by a bond, a–c by a record; b–d and c–d by records: a→d should go through c.
        func artist(_ id: String) -> Artist { Fixtures.artist(id, id, born: 1930, era: "modal") }
        func album(_ id: String, _ leader: String) -> Album { Fixtures.album(id, id, by: artist(leader), year: 1960) }
        func session(_ ids: [String]) -> Session {
            Session(reviewed: true, kind: nil, recorded: nil, recordedBetween: nil,
                    personnel: ids.map { Credit(artist: $0, name: $0, instruments: ["piano"], only: nil, except: nil, tracks: nil) },
                    crew: nil)
        }
        let lib = JazzLibrary(data: JazzData(eras: Fixtures.library.eras, artists: ["a", "b", "c", "d"].map(artist),
                                             albums: [album("ac", "a"), album("bd", "b"), album("cd", "c")], milestones: [],
                                             bonds: [Bond(a: "a", b: "b", kind: "band", note: "n")]),
                              sessions: ["ac": session(["a", "c"]), "bd": session(["b", "d"]), "cd": session(["c", "d"])])
        #expect(lib.path(from: "a", to: "d")?.map(\.to) == ["c", "d"])
    }
}

@Suite("Bundled ties")
struct BundledTieTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Every artist with a record in a reviewed session is on the map")
    func everyoneConnected() {
        let connected = Set(library.connectedArtists.map(\.id))
        for a in library.artists where library.isSideman(a.id) { #expect(connected.contains(a.id), "\(a.id)") }
    }

    @Test("Paths join distant eras")
    func paths() {
        let p = library.path(from: "scott-joplin", to: "nubya-garcia")
        #expect(p != nil)
        #expect((p?.count ?? 0) <= 12)
        #expect(library.path(from: "miles-davis", to: "john-coltrane")?.count == 1)
    }

    @Test func kindOfBlue() {
        let t = library.tie("miles-davis", "paul-chambers")
        #expect(t?.albums.contains { $0.id == "kind-of-blue" } == true)
    }
}
