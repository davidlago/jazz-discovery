import Foundation
import Testing

@MainActor
@Suite("Paths")
struct PathTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Start Here is the starter picks, in order")
    func startHere() throws {
        let path = try #require(library.journey("start-here"))
        #expect(path.stops.map(\.ref) == library.starterPath.map(\.id))
    }

    @Test("Every stop leads somewhere real")
    func stops() {
        #expect(library.paths.count >= 6)
        for p in library.paths {
            #expect(p.stops.count >= 4, "\(p.id)")
            for s in p.stops {
                switch s.kind {
                case .album: #expect(library.album(s.ref) != nil, "\(p.id): \(s.ref)")
                case .track: #expect(library.tracks[s.ref] != nil, "\(p.id): \(s.ref)")
                case .tune: #expect(library.tune(s.ref) != nil, "\(p.id): \(s.ref)")
                case .term: #expect(library.term(s.ref) != nil, "\(p.id): \(s.ref)")
                case .era: #expect(library.era(s.ref) != nil)
                case .artist: #expect(library.artist(s.ref) != nil)
                case .place: #expect(library.place(s.ref) != nil, "\(p.id): \(s.ref)")
                }
                if let t = s.track { #expect(library.tracks[t] != nil, "\(p.id): \(t)") }
            }
            for n in p.next { #expect(library.journey(n) != nil, "\(p.id) → \(n)") }
        }
    }

    @Test("Progress: heard records, played tracks and ticks count; un-ticking works; finishing needs every stop")
    func progress() throws {
        let passport = Passport(fileURL: nil, catalog: Passport.bundledCatalog(in: TestBundle.bundle))
        let path = try #require(library.journey("one-tune"))
        #expect(passport.progress(on: path, library: library).done == 0)
        #expect(passport.progress(on: path, library: library).next == 0)
        // The tune stop is read, then ticked.
        passport.setStop(path.stops[0].key, of: path.id, done: true)
        #expect(passport.progress(on: path, library: library).next == 1)
        // A track stop counts once its song has been heard in full.
        let t = try #require(library.playable(path.stops[1]))
        passport.listened(ListenEvent(songID: String(t.id), collectionId: nil, full: true))
        #expect(passport.progress(on: path, library: library).done == 2)
        passport.setStop(path.stops[0].key, of: path.id, done: false)
        #expect(passport.progress(on: path, library: library).done == 1)
        for s in path.stops { passport.setStop(s.key, of: path.id, done: true) }
        #expect(passport.isFinished(path, library: library))
        #expect(passport.currentPath(library: library)?.id != path.id)
    }

    @Test("Path progress merges across devices")
    func merge() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let a = PassportData(paths: ["x": ["album:a": t0]]), b = PassportData(paths: ["x": ["term:b": t0], "y": ["era:c": t0]])
        let m = PassportData.merged(a, b)
        #expect(m == PassportData.merged(b, a))
        #expect(m.paths?["x"]?.count == 2 && m.paths?["y"]?.count == 1)
    }
}
