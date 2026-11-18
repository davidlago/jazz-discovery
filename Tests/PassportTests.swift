import Foundation
import Testing

@MainActor
@Suite("Passport")
struct PassportTests {
    /// Kind of Blue has 5 tracks on Apple Music, Giant Steps 7.
    static let catalog: [String: CatalogAlbum] = [
        "kind-of-blue": CatalogAlbum(collectionId: 100, name: "Kind of Blue", artistName: "Miles Davis", artwork: nil,
                                     url: nil, releaseYear: 1959, trackCount: 5),
        "giant-steps": CatalogAlbum(collectionId: 200, name: "Giant Steps", artistName: "John Coltrane", artwork: nil,
                                    url: nil, releaseYear: 1960, trackCount: 7),
    ]
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func passport() -> Passport { Passport(fileURL: nil, catalog: Self.catalog) }
    func full(_ song: String, _ album: Int?, _ at: Date) -> ListenEvent { ListenEvent(songID: song, collectionId: album, full: true, at: at) }

    @Test func marksByHand() {
        let p = passport()
        #expect(!p.isHeard("kind-of-blue"))
        p.toggleHeard("kind-of-blue")
        #expect(p.isHeard("kind-of-blue"))
        #expect(p.mark("kind-of-blue")?.heard?.how == .hand)
        p.toggleSaved("kind-of-blue")
        p.toggleSaved(artist: "miles-davis")
        #expect(p.isSaved("kind-of-blue") && p.isSaved(artist: "miles-davis"))
        p.toggleHeard("kind-of-blue")
        #expect(!p.isHeard("kind-of-blue"))
        #expect(p.mark("kind-of-blue")?.heard?.on == false)   // kept as an un-mark, for syncing
        #expect(p.savedAlbums == ["kind-of-blue"] && p.heardCount == 0)
    }

    @Test("Heard after 60% of a record's tracks, each counted once")
    func heardByListening() {
        let p = passport()
        p.listened(full("1", 100, t0))
        p.listened(full("1", 100, t0 + 60))   // the same track again
        p.listened(full("2", 100, t0 + 120))
        #expect(!p.isHeard("kind-of-blue"))
        p.listened(full("3", 100, t0 + 180))  // 3 of 5
        #expect(p.isHeard("kind-of-blue"))
        #expect(p.mark("kind-of-blue")?.heard?.how == .listening)
        #expect(p.mark("kind-of-blue")?.heard?.at == t0 + 180)
        // Tracks from albums outside the Crate, or with no album, count for nothing.
        p.listened(full("9", 999, t0))
        p.listened(full("9", nil, t0))
        #expect(p.data.albums.count == 1)
    }

    @Test("Previews only ever sample")
    func previews() {
        let p = passport()
        for i in 1...7 { p.listened(ListenEvent(songID: "\(i)", collectionId: 200, full: false, at: t0)) }
        #expect(!p.isHeard("giant-steps"))
        #expect(p.isSampled("giant-steps"))
        #expect(p.mark("giant-steps")?.sampled == t0)
    }

    @Test("Un-marking starts the count over")
    func unmarkResets() {
        let p = passport()
        for i in 1...3 { p.listened(full("\(i)", 100, t0)) }
        p.setHeard("kind-of-blue", false, at: t0 + 10)
        p.listened(full("4", 100, t0 + 20))
        #expect(!p.isHeard("kind-of-blue"))
    }

    @Test func eraProgress() {
        let p = passport()
        p.setHeard("kind-of-blue", true)
        p.listened(ListenEvent(songID: "1", collectionId: 200, full: false, at: t0))
        let modal = p.progress(inEra: "modal", library: Fixtures.library)
        #expect(modal.heard == 1 && modal.sampled == 1 && modal.total == 3)
    }

    @Test("Saved to disk and read back")
    func persists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("passport-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Passport(fileURL: url, catalog: Self.catalog)
        p.setHeard("kind-of-blue", true, at: t0.addingTimeInterval(0.4))
        p.toggleSaved(artist: "john-coltrane")
        let q = Passport(fileURL: url, catalog: Self.catalog)
        #expect(q.data == p.data)
        // Reading back what's already there changes nothing.
        let before = q.data
        q.merge(p.data)
        #expect(q.data == before)
    }

    @Test func erase() {
        let p = passport()
        p.setHeard("kind-of-blue", true)
        p.erase()
        #expect(p.isEmpty && p.heardCount == 0)
    }
}

@Suite("Passport merge")
struct PassportMergeTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func data(_ marks: [String: PassportMark]) -> PassportData { PassportData(albums: marks) }

    @Test("Both orders give the same result")
    func symmetric() {
        let a = data(["x": PassportMark(heard: Flag(on: true, at: t0, how: .hand), sampled: t0 + 5, songs: ["1": t0]),
                      "y": PassportMark(saved: Flag(on: true, at: t0))])
        let b = data(["x": PassportMark(heard: Flag(on: false, at: t0), saved: Flag(on: true, at: t0 + 1),
                                        sampled: t0, songs: ["1": t0 + 9, "2": t0])])
        let ab = PassportData.merged(a, b), ba = PassportData.merged(b, a)
        #expect(ab == ba)
        #expect(ab.albums["x"]?.isHeard == true)        // same time: the yes wins
        #expect(ab.albums["x"]?.sampled == t0)          // the first sample
        #expect(ab.albums["x"]?.songs == ["1": t0, "2": t0])
        #expect(ab.albums["y"]?.isSaved == true)
    }

    @Test("A later un-mark wins, and a later mark after it wins again")
    func tombstones() {
        let marked = data(["x": PassportMark(heard: Flag(on: true, at: t0, how: .listening))])
        let cleared = data(["x": PassportMark(heard: Flag(on: false, at: t0 + 60))])
        #expect(PassportData.merged(marked, cleared).albums["x"]?.isHeard == false)
        let again = data(["x": PassportMark(heard: Flag(on: true, at: t0 + 120, how: .hand))])
        #expect(PassportData.merged(cleared, again).albums["x"]?.isHeard == true)
    }
}

@Suite("Last.fm import")
struct LastFMImportTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Matches the Crate by title and artist, ignoring editions")
    func matches() {
        let top = [
            LastFMImport.TopAlbum(artist: "Miles Davis", title: "Kind Of Blue (Legacy Edition)", plays: 40),
            LastFMImport.TopAlbum(artist: "John Coltrane", title: "A Love Supreme", plays: 12),
            LastFMImport.TopAlbum(artist: "Somebody Else", title: "Kind of Blue", plays: 99),
            LastFMImport.TopAlbum(artist: "Radiohead", title: "OK Computer", plays: 500),
        ]
        let m = LastFMImport.matches(top, library: library)
        #expect(m.map(\.album.id) == ["kind-of-blue", "a-love-supreme"])
        #expect(m[0].plays == 40)
    }
}
