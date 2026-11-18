import Foundation
import Testing

@Suite("JazzLibrary")
struct LibraryTests {
    let library = Fixtures.library

    @Test("Connections count both ways, once, and skip artists who aren't in the library")
    func connections() {
        // Miles lists Coltrane, Parker and "nobody"; Coltrane lists nobody, but Miles lists him.
        #expect(library.neighbors(of: "miles-davis") == ["john-coltrane", "charlie-parker"])
        #expect(library.neighbors(of: "john-coltrane") == ["miles-davis"])
        #expect(library.neighbors(of: "joao-gilberto").isEmpty)

        let pairs = library.edges.map { Set([$0.0, $0.1]) }
        #expect(pairs.count == 2)
        #expect(Set(pairs) == [["miles-davis", "john-coltrane"], ["miles-davis", "charlie-parker"]])
    }

    @Test func albumsByArtist() {
        // Listed albums and others led by the artist, in year order.
        #expect(library.albums(by: "miles-davis").map(\.id) == ["kind-of-blue", "bitches-brew"])
        #expect(library.albums(by: "john-coltrane").map(\.id) == ["giant-steps"])
        #expect(library.albums(by: "charlie-parker").isEmpty)
    }

    @Test func search() {
        #expect(library.search("joao").artists.map(\.id) == ["joao-gilberto"])
        #expect(library.search("  MILES ").artists.map(\.id) == ["miles-davis"])
        #expect(library.search("saxophone").artists.count == 2)
        #expect(library.search("columbia").albums.count == 2)
        #expect(library.search("1960").albums.map(\.id) == ["giant-steps"])
        #expect(library.search("").isEmpty)
    }

    @Test func decades() {
        #expect(library.decades.first == 1890)
        #expect(library.decades.last == 2020)
        #expect(library.eras(inDecade: 1950).map(\.id) == ["bebop", "latin", "modal"])
        #expect(library.albums(inDecade: 1950).map(\.id) == ["kind-of-blue"])
    }
}

@Suite("Bundled data")
struct BundledDataTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test func loads() {
        #expect(library.eras.count >= 14)
        #expect(library.artists.count >= 86)
        #expect(library.albums.count >= 88)
    }

    @Test("The links in the README and the screenshot script open real pages")
    func documentedLinks() {
        for s in ["jazzdiscovery://era/bebop", "jazzdiscovery://artist/miles-davis",
                  "jazzdiscovery://album/kind-of-blue", "jazzdiscovery://album/a-love-supreme",
                  "jazzdiscovery://decade/1950", "jazzdiscovery://connections/miles-davis"] {
            let link = DeepLink(URL(string: s)!, library: library)
            #expect(link != nil, "\(s)")
            if case .connections(let focus) = link { #expect(focus == "miles-davis") }
        }
        #expect(DeepLink(URL(string: "jazzdiscovery://play/album/a-love-supreme")!, library: library)
                == .playAlbum("a-love-supreme"))
    }

    @Test("Every decade link the app shows parses")
    func everyDecade() {
        for d in library.decades {
            #expect(DeepLink(URL(string: "jazzdiscovery://decade/\(d)")!, library: library) == .page(.decade(d)))
        }
    }
}
