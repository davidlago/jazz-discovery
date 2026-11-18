import Foundation
import Testing

@MainActor
@Suite("Listening guides")
struct GuideTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    private func timed(_ times: [Double?], duration: Double? = 300, songID: Int? = 42) -> Guide {
        Guide(id: "g", track: "Miles Davis|So What", songID: songID, duration: duration, intro: "i", form: "f",
              sections: times.enumerated().map { GuideSection(at: $1, kind: .solo, label: "s\($0)", note: "n") })
    }

    @Test("The section playing: boundaries, before the first, after the last")
    func sectionAt() {
        let g = timed([0, 30, 90])
        #expect(g.isTimed)
        #expect(g.section(at: 0) == 0)
        #expect(g.section(at: 29.9) == 0)
        #expect(g.section(at: 30) == 1)
        #expect(g.section(at: 299) == 2)
        #expect(g.section(at: 400) == 2)
        #expect(timed([5, 30]).section(at: 1) == 0)
        #expect(g.span(of: 2) == 90...300)
        #expect(g.span(of: 0) == 0...30)
    }

    @Test("Half-timed, unordered or lengthless guides aren't timed")
    func untimed() {
        #expect(!timed([0, nil, 90]).isTimed)
        #expect(!timed([0, 90, 30]).isTimed)
        #expect(!timed([0, 30], duration: nil).isTimed)
        #expect(!timed([0, 330]).isTimed)
        #expect(timed([0, nil]).section(at: 10) == nil)
    }

    @Test("Pinning: the same song, or the same title within two seconds; not a live version")
    func pinning() {
        let g = timed([0, 30])
        #expect(g.fits(songID: 42, title: nil, artist: nil, duration: 0))
        #expect(g.fits(songID: 7, title: "So What", artist: "Miles Davis", duration: 301.5))
        #expect(g.fits(songID: nil, title: "so what", artist: "Miles Davis & John Coltrane", duration: 299))
        #expect(!g.fits(songID: 7, title: "So What", artist: "Miles Davis", duration: 550))
        #expect(!g.fits(songID: 7, title: "So What (Live)", artist: "Miles Davis", duration: 300))
        #expect(!timed([0, nil]).fits(songID: 42, title: nil, artist: nil, duration: 0))
    }

    @Test("Every guide's recording, people and terms resolve")
    func data() {
        #expect(library.guides.count >= 6)
        for g in library.guides {
            #expect(library.tracks[g.track] != nil, "\(g.id)")
            if let a = g.album { #expect(library.album(a) != nil, "\(g.id)") }
            if let t = g.tune { #expect(library.tune(t) != nil, "\(g.id)") }
            #expect(g.sections.count >= 3, "\(g.id)")
            for s in g.sections {
                for t in s.terms { #expect(library.term(t) != nil, "\(g.id): \(t)") }
                for w in s.who where w.contains("-") && !w.contains(" ") { #expect(library.artist(w) != nil, "\(g.id): \(w)") }
            }
            #expect(library.guide(forTrack: g.track)?.id == g.id)
        }
    }

    @Test("Timed guides fit the recording the app plays for them")
    func timedFit() throws {
        let so = try #require(library.guide("so-what"))
        #expect(so.isTimed)
        for g in library.guides where g.isTimed {
            let t = try #require(library.tracks[g.track])
            let length = Double(t.track.durationMillis ?? 0) / 1000
            #expect(g.fits(songID: t.id, title: t.title, artist: t.artistName, duration: length), "\(g.id)")
            #expect(g.section(at: 0) == 0, "\(g.id)")
        }
    }

    @Test("What's playing finds its guide by the recording's song ID")
    func lookup() throws {
        let so = try #require(library.tracks["Miles Davis|So What"])
        #expect(library.guide(songID: so.id, title: nil, artist: nil, duration: 0)?.id == "so-what")
        #expect(library.guide(songID: 1, title: "Nope", artist: "Nobody", duration: 10) == nil)
    }

    @Test("Guide links open guides that exist")
    func links() {
        #expect(DeepLink(URL(string: "jazzdiscovery://guide/so-what")!, library: library) == .page(.guide("so-what")))
        #expect(DeepLink(URL(string: "jazzdiscovery://guide/nope")!, library: library) == nil)
        #expect(DeepLink(URL(string: "jazzdiscovery://guides")!, library: library) == .guides)
    }

    @Test("The JSON round-trips, keeping untimed sections untimed")
    func roundTrip() throws {
        let data = try JSONEncoder().encode(GuidesData(guides: library.guides))
        let back = try JSONDecoder().decode(GuidesData.self, from: data)
        #expect(back.guides == library.guides)
    }
}
