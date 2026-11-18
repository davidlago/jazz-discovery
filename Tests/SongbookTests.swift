import Foundation
import Testing

@Suite("Songbook")
struct SongbookTests {
    static func tune(_ id: String, _ title: String, aliases: [String]? = nil, builtOn: String? = nil, notOn: [String]? = nil,
                     years: [Int] = [1940, 1960, 1990]) -> Tune {
        Tune(id: id, title: title, composers: ["thelonious-monk"], year: 1940, origin: "Jazz original", form: "AABA",
             summary: "", builtOn: builtOn, aliases: aliases, notOn: notOn,
             versions: years.map { TuneVersion(artist: nil, artistName: "Someone", year: $0, note: "Listen.") })
    }

    let library: JazzLibrary = {
        let base = Fixtures.library
        return JazzLibrary(
            data: JazzData(eras: base.eras, artists: base.artists, albums: base.albums, milestones: []),
            tunes: [
                tune("round-midnight", "'Round Midnight", aliases: ["Round About Midnight", "'Round About Midnight"],
                     notOn: ["giant-steps"]),
                tune("i-got-rhythm", "I Got Rhythm"),
                tune("oleo", "Oleo", builtOn: "i-got-rhythm"),
                tune("anthropology", "Anthropology", builtOn: "i-got-rhythm"),
            ])
    }()

    @Test("Track titles find their tune: exact, aliases, punctuation and accents")
    func titleIndex() {
        #expect(library.tune(forTrackTitle: "'Round Midnight")?.id == "round-midnight")
        #expect(library.tune(forTrackTitle: "Round Midnight")?.id == "round-midnight")
        #expect(library.tune(forTrackTitle: "'Round About Midnight (Remastered)")?.id == "round-midnight")
        #expect(library.tune(forTrackTitle: "ROUND MIDNIGHT")?.id == "round-midnight")
        #expect(library.tune(forTrackTitle: "Blues") == nil)
        #expect(library.tune(forTrackTitle: "Round Midnight Blues") == nil)
    }

    @Test("notOn keeps a same-titled track on that album from matching")
    func notOn() {
        #expect(library.tune(forTrackTitle: "Round Midnight", onAlbum: "giant-steps") == nil)
        #expect(library.tune(forTrackTitle: "Round Midnight", onAlbum: "kind-of-blue")?.id == "round-midnight")
    }

    @Test("Families are symmetric for siblings and leave the tune out")
    func families() {
        let rhythm = library.tune("i-got-rhythm")!, oleo = library.tune("oleo")!, anthro = library.tune("anthropology")!
        #expect(Set(library.family(of: rhythm).map(\.id)) == ["oleo", "anthropology"])
        #expect(Set(library.family(of: oleo).map(\.id)) == ["i-got-rhythm", "anthropology"])
        #expect(library.family(of: anthro).contains(oleo))
        #expect(!library.family(of: oleo).contains(oleo))
    }

    @Test("Versions play oldest first; refs carry the year")
    func order() {
        let t = SongbookTests.tune("x", "X", years: [1990, 1940, 1960])
        #expect(t.sortedVersions.map(\.year) == [1940, 1960, 1990])
        #expect(t.versions[0].ref(in: t) == "Someone|X|1990")
        #expect(t.span == 1940...1990)
    }

    @Test("Decoding leaves optional fields out")
    func decoding() throws {
        let json = #"{"tunes":[{"id":"a","title":"A","composers":["Me"],"year":1950,"origin":"Blues","form":"12-bar","summary":"S","versions":[{"artist":null,"artistName":"Me","year":1950,"note":"N"}]}]}"#
        let book = try JSONDecoder().decode(SongbookData.self, from: Data(json.utf8))
        let first = book.tunes[0]
        #expect(first.aliases == nil)
        #expect(!first.versions[0].isLandmark)
    }
}

@Suite("Bundled Songbook")
struct BundledSongbookTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Every tune has at least three versions with notes, a landmark, and versions in two eras or 15 years apart")
    func shape() {
        #expect(library.tunes.count >= 24)
        for t in library.tunes {
            #expect(t.versions.count >= 3, "\(t.id)")
            let hasLandmark = t.versions.contains { $0.isLandmark }
            #expect(hasLandmark, "\(t.id)")
            let eras = Set(t.versions.compactMap { library.era(of: $0)?.id })
            #expect(t.span.upperBound - t.span.lowerBound >= 15 || eras.count >= 2, "\(t.id)")
            for v in t.versions { #expect(!v.note.isEmpty) }
        }
    }

    @Test("Most versions are resolved to Apple Music")
    func resolved() {
        let all = library.tunes.flatMap { t in t.versions.map { (t, $0) } }
        let found = all.filter { library.track(for: $0.1, of: $0.0) != nil }
        #expect(Double(found.count) / Double(all.count) > 0.8, "\(found.count) of \(all.count)")
    }
}
