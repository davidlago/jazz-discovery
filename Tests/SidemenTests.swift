import Foundation
import Testing

@Suite("Leaders and sidemen")
struct SidemenTests {
    let library = SessionTests.library

    @Test func leaders() {
        #expect(library.leads("miles-davis"))
        #expect(library.leads("john-coltrane"))
        #expect(!library.leads("charlie-parker"))   // in the guide, but no record of his in this fixture
        #expect(library.isSideman("john-coltrane") == false)   // leads Giant Steps
        #expect(library.isSideman("charlie-parker") == false)  // no records at all: not a sideman either
    }

    @Test func creditOnAnAlbum() {
        #expect(library.credit(of: "john-coltrane", on: "kind-of-blue")?.instruments == ["tenor saxophone"])
        #expect(library.credit(of: "john-coltrane", on: "bitches-brew") == nil)   // a draft
        #expect(library.credit(of: "charlie-parker", on: "kind-of-blue") == nil)
    }

    @Test("Connections draws only artists with someone to connect to")
    func connected() {
        let ids = Set(library.connectedArtists.map(\.id))
        #expect(ids == ["miles-davis", "john-coltrane", "charlie-parker"])
        #expect(!ids.contains("joao-gilberto"))
    }

    @Test("Search finds players who have no page, with their records")
    func searchPlayers() {
        let r = library.search("chambers")
        #expect(r.players.map(\.name) == ["Paul Chambers"])
        #expect(Set(r.players[0].albums.map(\.id)) == ["kind-of-blue", "giant-steps"])
        #expect(r.players[0].instruments == ["bass"])
        // Players with a page are artists, not players.
        #expect(library.search("coltrane").players.isEmpty)
        #expect(!library.search("coltrane").artists.isEmpty)
    }
}

@Suite("Bundled sidemen")
struct BundledSidemenTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Every page has records or tunes to show")
    func noEmptyPages() {
        for a in library.artists {
            #expect(library.leads(a.id) || !library.appearances(of: a.id).isEmpty || !a.signatureTracks.isEmpty, "\(a.id)")
        }
    }

    @Test("The sidemen are the 41 added with their credits, and each has signature tunes")
    func sidemen() {
        let sidemen = library.artists.filter { library.isSideman($0.id) }
        #expect(sidemen.count >= 41)
        for a in sidemen { #expect(!a.signatureTracks.isEmpty, "\(a.id)") }
        #expect(!library.isSideman("scott-joplin"))
        #expect(library.isSideman("paul-chambers"))
    }
}
